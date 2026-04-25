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
        nc.addObserver(self, selector: #selector(onMenuMightChange),
                       name: NSWindow.willCloseNotification, object: nil)
        if let mainMenu = NSApp.mainMenu {
            nc.addObserver(self, selector: #selector(onMenuMightChange),
                           name: NSMenu.didAddItemNotification, object: mainMenu)
        }
        DispatchQueue.main.async { [weak self] in self?.trimMenuBar() }
    }

    @objc private func onMenuMightChange() {
        // Defer to the next runloop tick so SwiftUI finishes attaching before we trim
        DispatchQueue.main.async { [weak self] in self?.trimMenuBar() }
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
