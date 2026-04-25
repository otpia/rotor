import Foundation

// .rotor 文件格式（v1）：JSON envelope，payload AES-256-GCM 加密，PBKDF2-SHA256 派生主密钥
// 以 magic + version 开头，保留未来升级空间（例如切 Argon2id）

struct BackupEnvelope: Codable {
    let magic: String
    let version: Int
    let kdf: BackupKDF
    let cipher: String
    let nonce: String        // base64(12 bytes)
    let ciphertext: String   // base64(ct + tag)
}

struct BackupKDF: Codable {
    let name: String         // "argon2id" (v2) 或 "pbkdf2-sha256" (v1)
    let salt: String         // base64(16 bytes)
    // pbkdf2-sha256 参数
    let iterations: Int?
    // argon2id 参数
    let opsLimit: Int?
    let memLimit: Int?
}

struct BackupPayload: Codable {
    let exportedAt: Date
    let accounts: [BackupAccount]
}

struct BackupAccount: Codable {
    let id: UUID
    let issuer: String
    let label: String
    let secret: String       // Base32
    let digits: Int
    let period: TimeInterval
    let algorithm: String    // sha1/sha256/sha512
    let iconSymbol: String
    let iconTintHex: String
    let sortOrder: Int
    let createdAt: Date
}
