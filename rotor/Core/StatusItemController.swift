import AppKit
import SwiftUI

extension Notification.Name {
    static let rotorShowMainWindow = Notification.Name("rotor.showMainWindow")
}

// Custom status bar item: left click toggles the popover, right click pops an NSMenu
// SwiftUI's MenuBarExtra can't distinguish left vs right click, and re-opening a closed WindowGroup isn't direct either
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    override private init() { super.init() }

    func install<Content: View>(@ViewBuilder popoverContent: () -> Content) {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 520)
        let hosting = NSHostingController(rootView: AnyView(popoverContent()))
        popover.contentViewController = hosting
        // Pre-load the view to trigger the SwiftUI body so .onReceive(...) is wired
        // and can receive "show main window" notifications even before the popover is shown
        _ = hosting.view
    }

    // Externally update the popover window level (mirrors the always-on-top setting)
    func applyPopoverLevel(_ level: NSWindow.Level) {
        popover.contentViewController?.view.window?.level = level
    }

    func applyPopoverSharingType(_ sharingType: NSWindow.SharingType) {
        popover.contentViewController?.view.window?.sharingType = sharingType
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRight {
            showContextMenu(from: sender)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo anchor: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    private func showContextMenu(from anchor: NSStatusBarButton) {
        let menu = NSMenu()

        let showMain = NSMenuItem(title: "显示主界面", action: #selector(menuShowMain), keyEquivalent: "")
        showMain.target = self
        menu.addItem(showMain)

        let settings = NSMenuItem(title: "设置…", action: #selector(menuShowSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出 Rotor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // NSStatusItem native behavior: assigning `menu` then performClick shows the menu; clear it immediately so left-click doesn't also turn into a menu
        statusItem?.menu = menu
        anchor.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuShowMain() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .rotorShowMainWindow, object: nil)
    }

    @objc private func menuShowSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Prefer the App menu's Settings… item (SwiftUI's Settings scene installs it automatically);
        // more reliable than sendAction: sendAction(nil target) walks the responder chain when there's no key window
        // and may fail to find a receiver for showSettingsWindow:
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for (index, item) in appMenu.items.enumerated() {
                let title = item.title.lowercased()
                if title.contains("setting") ||
                   title.contains("preference") ||
                   item.title.contains("设置") ||
                   item.title.contains("偏好") {
                    appMenu.performActionForItem(at: index)
                    return
                }
            }
        }
        // Fallback: try both the SwiftUI and legacy AppKit selectors
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
