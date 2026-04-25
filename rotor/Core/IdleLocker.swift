import AppKit
import Foundation
import Observation

// Listen for in-app mouse/keyboard/scroll events to reset the idle timer; calls VaultManager.lock() when the threshold is reached
@MainActor
final class IdleLocker {
    static let shared = IdleLocker()

    private var monitor: Any?
    private var lastActivity = Date()
    private var tickTimer: Timer?

    private init() {}

    func start() {
        stop()
        // Any user input counts as activity
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .flagsChanged]
        ) { [weak self] event in
            Task { @MainActor in
                self?.lastActivity = Date()
            }
            return event
        }
        // Poll every 30 seconds: precision is good enough, overhead is negligible
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
