import AppKit
import SwiftUI

extension Notification.Name {
    static let rotorShowMainWindow = Notification.Name("rotor.showMainWindow")
}

// 自建状态栏项：左键切换 popover，右键弹 NSMenu
// SwiftUI 的 MenuBarExtra 不支持区分左右键，且打开被关闭过的 WindowGroup 也不直接
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
        // 预加载 view 触发 SwiftUI body，保证 .onReceive(...)
        // 在 popover 尚未显示时也能接收「显示主界面」通知
        _ = hosting.view
    }

    // 外部更新 popover 窗口 level（跟随置顶设置）
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

        // NSStatusItem 原生：赋 menu 后 performClick 会显示菜单；立即清空避免左键也变 menu
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
        // 优先走 App 菜单里的 Settings… 菜单项（SwiftUI 的 Settings scene 自动挂了这一项），
        // 比 sendAction 更可靠：sendAction(nil target) 在没有 key window 时走 responder chain
        // 可能找不到 showSettingsWindow: 的接收者
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
        // fallback：SwiftUI / 老版本 AppKit 两个 selector 都试一下
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
