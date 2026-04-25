import Foundation
import Security

// 一次性迁移：keychain 存储 → 文件加密存储
// 1. 清空 legacy keychain（service = com.liasica.rotor.totp）
// 2. 删除 SwiftData 旧 store（ciphertext 字段新增，重建表最省事）
@MainActor
enum Migration {
    private static let defaultsKey = "rotor.migrated.keychain2file.v1"
    private static let legacyKeychainService = "com.liasica.rotor.totp"

    static func runOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }

        purgeLegacyKeychain()
        deleteLegacyStore()

        defaults.set(true, forKey: defaultsKey)
    }

    private static func purgeLegacyKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[Migration] keychain purge status: \(status)")
        }
    }

    private static func deleteLegacyStore() {
        let base = VaultKey.applicationSupportURL
        let names = ["default.store", "default.store-shm", "default.store-wal"]
        for name in names {
            let url = base.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
