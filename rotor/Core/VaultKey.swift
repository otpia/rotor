import CryptoKit
import Foundation

// 主加密密钥（32 字节随机）放在 App Sandbox 容器的 Application Support 下
// Sandboxed macOS app 的真实路径：~/Library/Containers/<bundle-id>/Data/Library/Application Support/
// 文件权限 0600；丢失即无法解密（未来可叠加主密码保护本文件）
enum VaultKey {
    private static let keyFileName = "vault.key"

    static func load() throws -> SymmetricKey {
        let url = try keyURL()
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let bytes = fresh.withUnsafeBytes { Data($0) }
        try writeAtomically(bytes, to: url, permissions: 0o600)
        return fresh
    }

    static var applicationSupportURL: URL {
        do {
            let url = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        } catch {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        }
    }

    private static func keyURL() throws -> URL {
        applicationSupportURL.appendingPathComponent(keyFileName)
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
