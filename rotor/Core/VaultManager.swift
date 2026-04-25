import CryptoKit
import Foundation
import Observation
import Sodium

// 保护模式开启时的 vault.master 文件：
// 用户主密码 Argon2id → 256-bit KEK → AES-256-GCM 加密 32B vault key
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
        case locked     // 保护模式开启且未解锁
        case unlocked   // vault key 在内存，可用
    }

    private(set) var state: State
    // 当前是否启用保护模式：true = vault.master 形式；false = vault.key 明文形式
    private(set) var protectionEnabled: Bool

    // 内存中的 vault key；锁定时 unset，引用被释放
    private var unlockedKey: SymmetricKey?

    private static let currentVersion = 1
    private static let argon2Ops = 3
    private static let argon2Mem = 64 * 1024 * 1024
    private static let masterFileName = "vault.master"
    private static let legacyFileName = "vault.key"

    private init() {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.masterURL.path) {
            // 保护开启：等待解锁
            state = .locked
            protectionEnabled = true
        } else if let keyData = try? Data(contentsOf: Self.legacyURL), keyData.count == 32 {
            // 保护关闭但 vault 已存在：直接 unlock
            unlockedKey = SymmetricKey(data: keyData)
            state = .unlocked
            protectionEnabled = false
        } else {
            // 首次启动：自动生成一个随机 vault key，保护默认关闭
            let freshKey = SymmetricKey(size: .bits256)
            try? Self.writeLegacyKey(freshKey)
            unlockedKey = freshKey
            state = .unlocked
            protectionEnabled = false
        }
    }

    // MARK: - 对外 key 访问

    func currentKey() -> SymmetricKey? { unlockedKey }

    // MARK: - 保护模式开关

    // 开启保护：要求当前处于 unlocked 状态；设置密码后把 vault.key 改写为 vault.master
    func enableProtection(password: String, confirm: String) throws {
        guard !protectionEnabled else { throw VaultManagerError.alreadyProtected }
        guard let key = unlockedKey else { throw VaultManagerError.locked }
        try validatePassword(password, confirm: confirm)
        try writeMasterFile(vaultKey: key, password: password)
        try? FileManager.default.removeItem(at: Self.legacyURL)
        protectionEnabled = true
        // state 保持 unlocked
    }

    // 关闭保护：要求输入当前主密码验证通过后，把 vault.master 改写回 vault.key
    func disableProtection(password: String) throws {
        guard protectionEnabled else { throw VaultManagerError.notProtected }
        let key = try readMasterFile(password: password)
        try Self.writeLegacyKey(key)
        try? FileManager.default.removeItem(at: Self.masterURL)
        unlockedKey = key
        protectionEnabled = false
        state = .unlocked
    }

    // MARK: - 锁定 / 解锁（仅保护模式下使用）

    func unlock(password: String) throws {
        guard protectionEnabled else { throw VaultManagerError.notProtected }
        let vaultKey = try readMasterFile(password: password)
        unlockedKey = vaultKey
        state = .unlocked
    }

    func lock() {
        // 未启用保护则 no-op
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

    // MARK: - 内部

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

    // MARK: - 文件路径 / I/O

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
