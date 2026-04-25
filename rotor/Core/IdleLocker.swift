import AppKit
import Foundation
import Observation

// 监听 app 内鼠标/键盘/滚轮事件重置 idle timer；达到阈值时调用 VaultManager.lock()
@MainActor
final class IdleLocker {
    static let shared = IdleLocker()

    private var monitor: Any?
    private var lastActivity = Date()
    private var tickTimer: Timer?

    private init() {}

    func start() {
        stop()
        // 任何用户输入都算活动
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .flagsChanged]
        ) { [weak self] event in
            Task { @MainActor in
                self?.lastActivity = Date()
            }
            return event
        }
        // 30 秒一次的轮询：精度够用，开销可忽略
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func noteActivity() {
        lastActivity = Date()
    }

    private func checkIdle() {
        let settings = SettingsStore.shared
        let vault = VaultManager.shared
        let minutes = settings.autoLockMinutes
        guard minutes > 0, vault.state == .unlocked else { return }
        let elapsed = Date().timeIntervalSince(lastActivity) / 60
        if elapsed >= Double(minutes) {
            vault.lock()
        }
    }
}
