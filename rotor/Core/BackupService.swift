import CommonCrypto
import CryptoKit
import Foundation
import Sodium

enum BackupError: LocalizedError {
    case emptyPassword
    case invalidFile
    case unsupportedVersion
    case unsupportedKDF
    case unsupportedCipher
    case decryptFailed
    case kdfFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassword:       return "请输入主密码"
        case .invalidFile:         return "不是有效的 .rotor 备份文件"
        case .unsupportedVersion:  return "备份版本不受支持"
        case .unsupportedKDF:      return "备份的 KDF 不受支持"
        case .unsupportedCipher:   return "备份的加密算法不受支持"
        case .decryptFailed:       return "密码错误或备份已损坏"
        case .kdfFailed:           return "密钥派生失败"
        case .decodeFailed:        return "备份内部数据无法解析"
        }
    }
}

enum BackupService {
    static let magic = "ROTOR"
    // v1: PBKDF2-SHA256；v2: Argon2id（OWASP 推荐首选）
    static let currentVersion = 2

    // Argon2id 参数：64 MiB / 3 轮；Apple Silicon 上约 0.5–1s，够抗 GPU 暴力破解
    static let argon2OpsLimit = 3
    static let argon2MemLimit = 64 * 1024 * 1024

    // 仅用于读取旧 v1 备份；新导出不再用
    static let legacyPbkdf2Iterations = 600_000

    // MARK: - Export

    static func export(accounts: [AccountModel], password: String) throws -> Data {
        guard !password.isEmpty else { throw BackupError.emptyPassword }

        let items: [BackupAccount] = try accounts.map { account in
            let secret = try SecretVault.decrypt(account.ciphertext)
            return BackupAccount(
                id: account.id,
                issuer: account.issuer,
                label: account.label,
                secret: Base32.encode(secret),
                digits: account.digits,
                period: account.period,
                algorithm: account.algorithm.rawValue,
                iconSymbol: account.iconSymbol,
                iconTintHex: account.iconTintHex,
                sortOrder: account.sortOrder,
                createdAt: account.createdAt
            )
        }
        let payload = BackupPayload(exportedAt: Date(), accounts: items)

        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        let plaintext = try payloadEncoder.encode(payload)

        let salt = randomBytes(16)
        let nonceBytes = randomBytes(12)
        let keyData = try deriveArgon2id(
            password: password,
            salt: salt,
            opsLimit: argon2OpsLimit,
            memLimit: argon2MemLimit
        )
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        let ctWithTag = sealed.ciphertext + sealed.tag

        let envelope = BackupEnvelope(
            magic: magic,
            version: currentVersion,
            kdf: BackupKDF(
                name: "argon2id",
                salt: salt.base64EncodedString(),
                iterations: nil,
                opsLimit: argon2OpsLimit,
                memLimit: argon2MemLimit
            ),
            cipher: "aes-256-gcm",
            nonce: nonceBytes.base64EncodedString(),
            ciphertext: ctWithTag.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // MARK: - Import

    static func `import`(from data: Data, password: String) throws -> [BackupAccount] {
        guard !password.isEmpty else { throw BackupError.emptyPassword }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }

        guard envelope.magic == magic else { throw BackupError.invalidFile }
        // 支持读取 v1（PBKDF2）和 v2（Argon2id）
        guard envelope.version == 1 || envelope.version == 2 else {
            throw BackupError.unsupportedVersion
        }
        guard envelope.cipher == "aes-256-gcm" else { throw BackupError.unsupportedCipher }

        guard let salt = Data(base64Encoded: envelope.kdf.salt),
              let nonceData = Data(base64Encoded: envelope.nonce),
              let combined = Data(base64Encoded: envelope.ciphertext),
              combined.count >= 16 else {
            throw BackupError.invalidFile
        }

        let keyData: Data
        switch envelope.kdf.name {
        case "argon2id":
            guard let ops = envelope.kdf.opsLimit,
                  let mem = envelope.kdf.memLimit else {
                throw BackupError.invalidFile
            }
            keyData = try deriveArgon2id(
                password: password,
                salt: salt,
                opsLimit: ops,
                memLimit: mem
            )
        case "pbkdf2-sha256":
            guard let iter = envelope.kdf.iterations else {
                throw BackupError.invalidFile
            }
            keyData = try derivePBKDF2(password: password, salt: salt, iterations: iter)
        default:
            throw BackupError.unsupportedKDF
        }

        let key = SymmetricKey(data: keyData)
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
        } catch {
            throw BackupError.invalidFile
        }

        let ct = combined.prefix(combined.count - 16)
        let tag = combined.suffix(16)
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        } catch {
            throw BackupError.invalidFile
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.decryptFailed
        }

        do {
            let payload = try decoder.decode(BackupPayload.self, from: plaintext)
            return payload.accounts
        } catch {
            throw BackupError.decodeFailed
        }
    }

    // MARK: - KDFs

    private static func deriveArgon2id(
        password: String,
        salt: Data,
        opsLimit: Int,
        memLimit: Int
    ) throws -> Data {
        let sodium = Sodium()
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        // libsodium 要求 salt 长度 = crypto_pwhash_SALTBYTES = 16
        guard saltBytes.count == sodium.pwHash.SaltBytes else {
            throw BackupError.kdfFailed
        }
        guard let derived = sodium.pwHash.hash(
            outputLength: 32,
            passwd: passwordBytes,
            salt: saltBytes,
            opsLimit: opsLimit,
            memLimit: memLimit,
            alg: .Argon2ID13
        ) else {
            throw BackupError.kdfFailed
        }
        return Data(derived)
    }

    private static func derivePBKDF2(password: String, salt: Data, iterations: Int) throws -> Data {
        var derived = Data(count: 32)
        let passwordData = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPtr -> Int32 in
            passwordData.withUnsafeBytes { pwPtr -> Int32 in
                salt.withUnsafeBytes { saltPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.kdfFailed }
        return derived
    }

    private static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return data
    }
}
