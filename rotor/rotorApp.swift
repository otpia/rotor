import AppKit
import SwiftData
import SwiftUI

@main
struct RotorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore.shared

    private let container: ModelContainer

    init() {
        FontRegistrar.registerBundledFonts()
        Migration.runOnceIfNeeded()
        do {
            container = try ModelContainer(for: AccountModel.self)
        } catch {
            fatalError("无法初始化 SwiftData 容器：\(error)")
        }
        // Demo seed is deferred to MainView onAppear after the vault unlocks; SecretVault is unavailable while locked

        let capturedContainer = container
        StatusItemController.shared.install {
            PopoverView()
                .modelContainer(capturedContainer)
        }

        // Start idle monitoring
        IdleLocker.shared.start()
    }

    // Keep popover-only level sync here; the main window is handled by WindowAccessor
    // (the popover's own WindowAccessor is applied directly inside PopoverView)

    var body: some Scene {
        // Read settings in body so @Observable tracks them and re-evaluates
        // when toggles change; otherwise WindowAccessor applies stale values
        let mainLevel: NSWindow.Level = settings.mainWindowPinned ? .floating : .normal
        let sharingType: NSWindow.SharingType = settings.screenCaptureBlocked ? .none : .readOnly

        // Window (not WindowGroup): single instance; openWindow(id:) re-shows it after close
        Window("Rotor", id: "main") {
            MainView()
                .background(
                    WindowAccessor(level: mainLevel, sharingType: sharingType)
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) { EmptyView() }
        }

        Settings {
            SettingsView(settings: settings)
                .modelContainer(container)
                .background(
                    WindowAccessor(level: .floating, sharingType: sharingType)
                )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .rotorShowMainWindow, object: nil)
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI re-attaches commands across Scene lifecycle changes (main window close/reopen),
        // bringing back View / Help menus etc., so we listen to several events and re-trim idempotently
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onMenuMightChange),
                       name: NSApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(onMenuMightChange),
                       name: NSWindow.didBecomeMainNotification, object: nil)
        nc.addObserver(self, selector: #selector(onWindowWillClose(_:)),
                       name: NSWindow.willCloseNotification, object: nil)
        if let mainMenu = NSApp.mainMenu {
            nc.addObserver(self, selector: #selector(onMenuMightChange),
                           name: NSMenu.didAddItemNotification, object: mainMenu)
        }
        // Switch back to regular (Dock + ⌘Tab) whenever the main window is being shown
        nc.addObserver(self, selector: #selector(onShowMainWindow),
                       name: .rotorShowMainWindow, object: nil)
        DispatchQueue.main.async { [weak self] in self?.trimMenuBar() }
    }

    @objc private func onMenuMightChange() {
        // Defer to the next runloop tick so SwiftUI finishes attaching before we trim
        DispatchQueue.main.async { [weak self] in self?.trimMenuBar() }
    }

    @objc private func onWindowWillClose(_ note: Notification) {
        onMenuMightChange()
        guard let closing = note.object as? NSWindow else { return }
        // Scope to the main scene: SwiftUI sets the NSWindow title to the Scene title.
        // Panels (popover host, status item) are excluded; Settings has its own title.
        guard !(closing is NSPanel), closing.title == "Rotor" else { return }
        DispatchQueue.main.async { [weak self] in self?.demoteToAccessory(except: closing) }
    }

    @objc private func onShowMainWindow() {
        // Must be regular before openWindow / activate, otherwise the window
        // may not key in front and the Dock icon stays hidden
        NSApp.setActivationPolicy(.regular)
    }

    private func demoteToAccessory(except closing: NSWindow) {
        // If the user still has another standard window open (e.g. Settings),
        // keep regular. Otherwise become an accessory app: no Dock, no ⌘Tab.
        let hasOther = NSApp.windows.contains { window in
            guard window !== closing else { return false }
            guard window.isVisible, !(window is NSPanel) else { return false }
            return window.styleMask.contains(.titled)
        }
        guard !hasOther else { return }
        NSApp.setActivationPolicy(.accessory)
        // setActivationPolicy doesn't immediately refresh the ⌘Tab list while
        // the app is still the active app. Forcing a hide deactivates us so
        // AppKit republishes the new policy and we drop out of the switcher.
        NSApp.hide(nil)
    }

    private func trimMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let appMenuItem = mainMenu.items.first else { return }
        // Keep the Edit menu so standard editing shortcuts (⌘A select all,
        // ⌘C/⌘V/⌘X cut copy paste, ⌘Z undo) keep working in TextField
        let editMenuItem = mainMenu.items.first { menuItem in
            guard let submenu = menuItem.submenu else { return false }
            return submenu.items.contains { $0.action == #selector(NSText.selectAll(_:)) }
        }
        let windowMenuItem = mainMenu.items.first { $0.submenu === NSApp.windowsMenu }
        let keep = [appMenuItem, editMenuItem, windowMenuItem].compactMap { $0 }
        // Skip removeItem if only the keep set remains, to avoid didAddItem/remove churn loops
        if mainMenu.items.count == keep.count { return }
        for item in Array(mainMenu.items) where !keep.contains(where: { $0 === item }) {
            mainMenu.removeItem(item)
        }
    }
}
