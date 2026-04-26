import Foundation
import Observation

enum AccountSortMode: String, CaseIterable, Identifiable {
    case manual        // User-defined order (sortOrder)
    case alphabetical  // By issuer name, A→Z
    case recent        // By creation time, newest first

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .manual:        return "自定义顺序"
        case .alphabetical:  return "按名称"
        case .recent:        return "最近添加"
        }
    }
}

// App settings persisted via UserDefaults; swap the storage layer when migrating to a SQLite settings table later
@Observable
final class SettingsStore {
    @MainActor static let shared = SettingsStore()

    var mainWindowPinned: Bool {
        didSet { UserDefaults.standard.set(mainWindowPinned, forKey: Keys.mainWindowPinned) }
    }

    var popoverPinned: Bool {
        didSet { UserDefaults.standard.set(popoverPinned, forKey: Keys.popoverPinned) }
    }

    // Screen recording / screenshot blocking (NSWindow.sharingType = .none); enabled by default
    var screenCaptureBlocked: Bool {
        didSet { UserDefaults.standard.set(screenCaptureBlocked, forKey: Keys.screenCaptureBlocked) }
    }

    var sortMode: AccountSortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: Keys.sortMode) }
    }

    // Auto-lock after idle (in minutes); 0 = never lock
    var autoLockMinutes: Int {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: Keys.autoLockMinutes) }
    }

    // Whether to silently check GitHub Releases for a newer version on launch
    var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    // The version string the user chose to skip (e.g. "1.0.5"); empty when none
    var skippedUpdateVersion: String {
        didSet { UserDefaults.standard.set(skippedUpdateVersion, forKey: Keys.skippedUpdateVersion) }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.screenCaptureBlocked: true,
            Keys.sortMode: AccountSortMode.manual.rawValue,
            Keys.autoLockMinutes: 5,
            Keys.autoCheckUpdates: true,
            Keys.skippedUpdateVersion: "",
        ])

        self.mainWindowPinned       = d.bool(forKey: Keys.mainWindowPinned)
        self.popoverPinned          = d.bool(forKey: Keys.popoverPinned)
        self.screenCaptureBlocked   = d.bool(forKey: Keys.screenCaptureBlocked)
        self.sortMode               = AccountSortMode(rawValue: d.string(forKey: Keys.sortMode) ?? "") ?? .manual
        self.autoLockMinutes        = d.integer(forKey: Keys.autoLockMinutes)
        self.autoCheckUpdates       = d.bool(forKey: Keys.autoCheckUpdates)
        self.skippedUpdateVersion   = d.string(forKey: Keys.skippedUpdateVersion) ?? ""
    }

    private enum Keys {
        static let mainWindowPinned      = "rotor.mainWindowPinned"
        static let popoverPinned         = "rotor.popoverPinned"
        static let screenCaptureBlocked  = "rotor.screenCaptureBlocked"
        static let sortMode              = "rotor.sortMode"
        static let autoLockMinutes       = "rotor.autoLockMinutes"
        static let autoCheckUpdates      = "rotor.autoCheckUpdates"
        static let skippedUpdateVersion  = "rotor.skippedUpdateVersion"
    }
}
