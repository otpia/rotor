import Foundation
import Security
import SwiftData

// One-time migration: keychain storage → file-based encrypted storage
// 1. Purge the legacy keychain (service = com.liasica.rotor.totp)
// 2. Delete the old SwiftData store (the new ciphertext field makes a clean rebuild simplest)
@MainActor
enum Migration {
    private static let defaultsKey = "rotor.migrated.keychain2file.v1"
    private static let demoCleanupKey = "rotor.migrated.demoCleanup.v1"
    private static let legacyKeychainService = "com.liasica.rotor.totp"

    // RFC 6238 test secret used by every prior demo seed entry; safe to match
    // because no real provisioning workflow ever hands this out
    private static let demoSecretBase32 = "JBSWY3DPEHPK3PXP"

    static func runOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }

        purgeLegacyKeychain()
        deleteLegacyStore()

        defaults.set(true, forKey: defaultsKey)
    }

    // Removes any leftover demo-seeded accounts (Sony / Google / Discord / Aliyun / GitHub
    // populated on early launches). Called from MainView once the vault is unlocked
    // because decrypting ciphertexts needs the in-memory key.
    static func cleanupDemoSeedIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: demoCleanupKey) else { return }
        guard let demoSecret = Base32.decode(demoSecretBase32) else { return }

        let fd = FetchDescriptor<AccountModel>()
        let all = (try? context.fetch(fd)) ?? []
        var deleted = 0
        for account in all {
            guard let secret = try? SecretVault.decrypt(account.ciphertext) else { continue }
            if secret == demoSecret {
                context.delete(account)
                deleted += 1
            }
        }
        if deleted > 0 { try? context.save() }
        defaults.set(true, forKey: demoCleanupKey)
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
