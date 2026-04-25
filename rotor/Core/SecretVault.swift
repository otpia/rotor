import CryptoKit
import Foundation

// AES-256-GCM wrapper; sealed.combined contains nonce(12) + ciphertext + tag(16)
// The vault key is now owned by VaultManager (held in memory, protected by the master password)
@MainActor
enum SecretVault {
    enum VaultError: Error {
        case locked
        case sealFailed
    }

    static func encrypt(_ plain: Data) throws -> Data {
        guard let key = VaultManager.shared.currentKey() else { throw VaultError.locked }
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw VaultError.sealFailed }
        return combined
    }

    static func decrypt(_ combined: Data) throws -> Data {
        guard let key = VaultManager.shared.currentKey() else { throw VaultError.locked }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }
}
