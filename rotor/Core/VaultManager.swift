import CryptoKit
import Foundation
import Observation
import Sodium

// vault.master file used when protection mode is enabled:
// user master password → Argon2id → 256-bit KEK → AES-256-GCM encrypts a 32-byte vault key
struct MasterVaultFile: Codable {
    let version: Int
    let kdf: KDFParams
    let nonce: String
    let ciphertext: String

    struct KDFParams: Codable {
        let name: String
        let salt: String
        let opsLimit: Int
        let memLimit: Int
    }
}

enum VaultManagerError: LocalizedError {
    case passwordTooShort
    case passwordMismatch
    case wrongPassword
    case corruptFile
    case kdfFailed
    case locked
    case alreadyProtected
    case notProtected

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:    return "主密码至少 8 位"
        case .passwordMismatch:    return "两次输入的密码不一致"
        case .wrongPassword:       return "密码错误"
        case .corruptFile:         return "主密钥文件已损坏"
        case .kdfFailed:           return "密钥派生失败"
        case .locked:              return "Rotor 已锁定"
        case .alreadyProtected:    return "保护模式已开启"
        case .notProtected:        return "保护模式未开启"
        }
    }
}

@Observable @MainActor
final class VaultManager {
    static let shared = VaultManager()

    enum State: Equatable {
        case locked     // protection enabled and not yet unlocked
        case unlocked   // vault key resident in memory, ready to use
    }

    private(set) var state: State
    // Whether protection mode is currently enabled: true = vault.master form; false = plain vault.key form
    private(set) var protectionEnabled: Bool

    // In-memory vault key; cleared (reference released) when locked
    private var unlockedKey: SymmetricKey?

    private static let currentVersion = 1
    private static let argon2Ops = 3
    private static let argon2Mem = 64 * 1024 * 1024
    private static let masterFileName = "vault.master"
    private static let legacyFileName = "vault.key"

    private init() {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.masterURL.path) {
            // Protection enabled: wait for unlock
            state = .locked
            protectionEnabled = true
        } else if let keyData = try? Data(contentsOf: Self.legacyURL), keyData.count == 32 {
            // Protection disabled but vault already exists: unlock directly
            unlockedKey = SymmetricKey(data: keyData)
            state = .unlocked
            protectionEnabled = false
        } else {
            // First launch: auto-generate a random vault key; protection defaults to off
            let freshKey = SymmetricKey(size: .bits256)
            try? Self.writeLegacyKey(freshKey)
            unlockedKey = freshKey
            state = .unlocked
            protectionEnabled = false
        }
    }

    // MARK: - External key access

    func currentKey() -> SymmetricKey? { unlockedKey }

    // MARK: - Protection mode toggle

    // Enable protection: requires the current state to be unlocked; rewrites vault.key into vault.master after setting the password
    func enableProtection(password: String, confirm: String) throws {
        guard !protectionEnabled else { throw VaultManagerError.alreadyProtected }
        guard let key = unlockedKey else { throw VaultManagerError.locked }
        try validatePassword(password, confirm: confirm)
        try writeMasterFile(vaultKey: key, password: password)
        try? FileManager.default.removeItem(at: Self.legacyURL)
        protectionEnabled = true
        // state stays unlocked
    }

    // Disable protection: after verifying the current master password, rewrite vault.master back to vault.key
    func disableProtection(password: String) throws {
        guard protectionEnabled else { throw VaultManagerError.notProtected }
        let key = try readMasterFile(password: password)
        try Self.writeLegacyKey(key)
        try? FileManager.default.removeItem(at: Self.masterURL)
        unlockedKey = key
        protectionEnabled = false
        state = .unlocked
    }

    // MARK: - Lock / unlock (only used when protection is enabled)

    func unlock(password: String) throws {
        guard protectionEnabled else { throw VaultManagerError.notProtected }
        let vaultKey = try readMasterFile(password: password)
        unlockedKey = vaultKey
        state = .unlocked
    }

    func lock() {
        // No-op when protection is disabled
        guard protectionEnabled else { return }
        unlockedKey = nil
        state = .locked
    }

    func changePassword(oldPassword: String, newPassword: String, confirm: String) throws {
        guard protectionEnabled else { throw VaultManagerError.notProtected }
        try validatePassword(newPassword, confirm: confirm)
        let vaultKey = try readMasterFile(password: oldPassword)
        try writeMasterFile(vaultKey: vaultKey, password: newPassword)
        unlockedKey = vaultKey
        state = .unlocked
    }

    // MARK: - Internal

    private func validatePassword(_ password: String, confirm: String) throws {
        guard password.count >= 8 else { throw VaultManagerError.passwordTooShort }
        guard password == confirm else { throw VaultManagerError.passwordMismatch }
    }

    private func writeMasterFile(vaultKey: SymmetricKey, password: String) throws {
        let salt = Self.randomBytes(16)
        let nonceBytes = Self.randomBytes(12)
        let kek = try deriveKEK(password: password, salt: salt)
        let keyData = vaultKey.withUnsafeBytes { Data($0) }
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(keyData, using: kek, nonce: nonce)
        let ctWithTag = sealed.ciphertext + sealed.tag

        let file = MasterVaultFile(
            version: Self.currentVersion,
            kdf: .init(
                name: "argon2id",
                salt: salt.base64EncodedString(),
                opsLimit: Self.argon2Ops,
                memLimit: Self.argon2Mem
            ),
            nonce: nonceBytes.base64EncodedString(),
            ciphertext: ctWithTag.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)

        try Self.writeAtomically(data, to: Self.masterURL, permissions: 0o600)
    }

    private func readMasterFile(password: String) throws -> SymmetricKey {
        let data = try Data(contentsOf: Self.masterURL)
        let decoder = JSONDecoder()
        let file: MasterVaultFile
        do { file = try decoder.decode(MasterVaultFile.self, from: data) }
        catch { throw VaultManagerError.corruptFile }
        guard file.version == Self.currentVersion,
              file.kdf.name == "argon2id",
              let salt = Data(base64Encoded: file.kdf.salt),
              let nonceBytes = Data(base64Encoded: file.nonce),
              let combined = Data(base64Encoded: file.ciphertext),
              combined.count >= 16 else {
            throw VaultManagerError.corruptFile
        }
        let kek = try deriveKEK(
            password: password,
            salt: salt,
            opsLimit: file.kdf.opsLimit,
            memLimit: file.kdf.memLimit
        )
        let nonce: AES.GCM.Nonce
        do { nonce = try AES.GCM.Nonce(data: nonceBytes) }
        catch { throw VaultManagerError.corruptFile }
        let ct = combined.prefix(combined.count - 16)
        let tag = combined.suffix(16)
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag) }
        catch { throw VaultManagerError.corruptFile }

        let keyData: Data
        do { keyData = try AES.GCM.open(box, using: kek) }
        catch { throw VaultManagerError.wrongPassword }
        guard keyData.count == 32 else { throw VaultManagerError.corruptFile }
        return SymmetricKey(data: keyData)
    }

    private func deriveKEK(
        password: String,
        salt: Data,
        opsLimit: Int = VaultManager.argon2Ops,
        memLimit: Int = VaultManager.argon2Mem
    ) throws -> SymmetricKey {
        let sodium = Sodium()
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        guard saltBytes.count == sodium.pwHash.SaltBytes else {
            throw VaultManagerError.kdfFailed
        }
        guard let derived = sodium.pwHash.hash(
            outputLength: 32,
            passwd: passwordBytes,
            salt: saltBytes,
            opsLimit: opsLimit,
            memLimit: memLimit,
            alg: .Argon2ID13
        ) else {
            throw VaultManagerError.kdfFailed
        }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - File paths / I/O

    static var applicationSupportURL: URL { VaultKey.applicationSupportURL }
    private static var masterURL: URL { applicationSupportURL.appendingPathComponent(masterFileName) }
    private static var legacyURL: URL { applicationSupportURL.appendingPathComponent(legacyFileName) }

    private static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return data
    }

    private static func writeLegacyKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        try writeAtomically(data, to: legacyURL, permissions: 0o600)
    }

    private static func writeAtomically(_ data: Data, to url: URL, permissions: Int) throws {
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: tmp.path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}
