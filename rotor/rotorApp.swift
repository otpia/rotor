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
        // Demo seed 延到 vault 解锁后由 MainView onAppear 触发；锁定态下 SecretVault 不可用

        let capturedContainer = container
        StatusItemController.shared.install {
            PopoverView()
                .modelContainer(capturedContainer)
        }

        // 启动空闲监听
        IdleLocker.shared.start()
    }

    // 单独保留 popover 的 level 同步逻辑：主窗口已由 WindowAccessor 处理
    // （popover 自身的 WindowAccessor 在 PopoverView 里直接 apply）

    var body: some Scene {
        // Window（非 WindowGroup）：单实例，关闭后 openWindow(id:) 可重新显示
        Window("Rotor", id: "main") {
            MainView()
                .background(
                    WindowAccessor { window in
                        applyWindowPrefs(window, pinned: settings.mainWindowPinned)
                    }
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
                    WindowAccessor { window in
                        applyWindowPrefs(window, level: .floating)
                    }
                )
        }
    }

    // 统一给 SwiftUI 管理的 NSWindow 应用 level + sharingType
    // 截图防护用 .none：整块窗口在录屏/截图中不可见
    private func applyWindowPrefs(
        _ window: NSWindow?,
        pinned: Bool = false,
        level explicitLevel: NSWindow.Level? = nil
    ) {
        guard let window else { return }
        window.level = explicitLevel ?? (pinned ? .floating : .normal)
        window.sharingType = settings.screenCaptureBlocked ? .none : .readOnly
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
        // SwiftUI 在 Scene 生命周期变化（主窗口关闭再开）时会重挂 commands，
        // 导致 View / Help 等菜单回来，所以监听多个事件幂等地重 trim
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
        // 推迟到下一个 runloop tick，等 SwiftUI 挂完再 trim
        DispatchQueue.main.async { [weak self] in self?.trimMenuBar() }
    }

    private func trimMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let appMenuItem = mainMenu.items.first else { return }
        let windowMenuItem = mainMenu.items.first { $0.submenu === NSApp.windowsMenu }
        let keep = [appMenuItem, windowMenuItem].compactMap { $0 }
        // 已经只剩 keep 不重复 removeItem，避免 didAddItem/remove 循环抖动
        if mainMenu.items.count == keep.count { return }
        for item in Array(mainMenu.items) where !keep.contains(where: { $0 === item }) {
            mainMenu.removeItem(item)
        }
    }
}
