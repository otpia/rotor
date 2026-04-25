import CryptoKit
import Foundation

// AES-256-GCM 封装；sealed.combined 包含 nonce(12) + ciphertext + tag(16)
// vault key 现在由 VaultManager 管理（内存持有，受主密码保护）
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
