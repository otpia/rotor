import Foundation
import Observation

enum AccountSortMode: String, CaseIterable, Identifiable {
    case manual        // 用户自定义顺序（sortOrder）
    case alphabetical  // 按 issuer 名称 A→Z
    case recent        // 按添加时间倒序

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .manual:        return "自定义顺序"
        case .alphabetical:  return "按名称"
        case .recent:        return "最近添加"
        }
    }
}

// 应用设置（UserDefaults 持久化）；后续迁移到 SQLite settings 表时改存储层即可
@Observable
final class SettingsStore {
    @MainActor static let shared = SettingsStore()

    var mainWindowPinned: Bool {
        didSet { UserDefaults.standard.set(mainWindowPinned, forKey: Keys.mainWindowPinned) }
    }

    var popoverPinned: Bool {
        didSet { UserDefaults.standard.set(popoverPinned, forKey: Keys.popoverPinned) }
    }

    // 屏幕录制 / 截图防护（NSWindow.sharingType = .none）；默认开启
    var screenCaptureBlocked: Bool {
        didSet { UserDefaults.standard.set(screenCaptureBlocked, forKey: Keys.screenCaptureBlocked) }
    }

    var sortMode: AccountSortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: Keys.sortMode) }
    }

    // 空闲自动锁定（分钟）；0 = 永不锁定
    var autoLockMinutes: Int {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: Keys.autoLockMinutes) }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.screenCaptureBlocked: true,
            Keys.sortMode: AccountSortMode.manual.rawValue,
            Keys.autoLockMinutes: 5,
        ])

        self.mainWindowPinned      = d.bool(forKey: Keys.mainWindowPinned)
        self.popoverPinned         = d.bool(forKey: Keys.popoverPinned)
        self.screenCaptureBlocked  = d.bool(forKey: Keys.screenCaptureBlocked)
        self.sortMode              = AccountSortMode(rawValue: d.string(forKey: Keys.sortMode) ?? "") ?? .manual
        self.autoLockMinutes       = d.integer(forKey: Keys.autoLockMinutes)
    }

    private enum Keys {
        static let mainWindowPinned      = "rotor.mainWindowPinned"
        static let popoverPinned         = "rotor.popoverPinned"
        static let screenCaptureBlocked  = "rotor.screenCaptureBlocked"
        static let sortMode              = "rotor.sortMode"
        static let autoLockMinutes       = "rotor.autoLockMinutes"
    }
}
