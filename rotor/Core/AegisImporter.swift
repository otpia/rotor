import Foundation

enum AegisImportError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case encryptedNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidFormat:         return "不是有效的 Aegis 备份 JSON"
        case .unsupportedVersion:    return "Aegis 备份版本不受支持"
        case .encryptedNotSupported: return "此 Aegis 备份已加密，暂不支持；请先在 Aegis 中导出未加密 JSON"
        }
    }
}

// https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md
enum AegisImporter {
    static func parse(_ data: Data) throws -> [AccountImportService.Candidate] {
        let decoder = JSONDecoder()

        if let plain = try? decoder.decode(AegisWrapperPlain.self, from: data) {
            guard plain.version == 1 else { throw AegisImportError.unsupportedVersion }
            return plain.db.entries.compactMap(toCandidate)
        }

        if (try? decoder.decode(AegisWrapperEncrypted.self, from: data)) != nil {
            throw AegisImportError.encryptedNotSupported
        }

        throw AegisImportError.invalidFormat
    }

    private static func toCandidate(_ entry: AegisEntry) -> AccountImportService.Candidate? {
        guard entry.type.lowercased() == "totp" else { return nil }
        let algo: TOTPAlgorithm
        switch (entry.info.algo ?? "SHA1").uppercased() {
        case "SHA256": algo = .sha256
        case "SHA512": algo = .sha512
        default:       algo = .sha1
        }
        let uuid = entry.uuid.flatMap(UUID.init(uuidString:))
        let issuer = entry.issuer?.isEmpty == false ? entry.issuer : nil
        return AccountImportService.Candidate(
            id: uuid,
            issuer: issuer,
            label: entry.name,
            secretBase32: entry.info.secret,
            digits: entry.info.digits ?? 6,
            period: TimeInterval(entry.info.period ?? 30),
            algorithm: algo
        )
    }

    private struct AegisWrapperPlain: Decodable {
        let version: Int
        let db: AegisDB
    }

    private struct AegisWrapperEncrypted: Decodable {
        let version: Int
        let db: String          // In encrypted mode `db` is a base64 string
    }

    private struct AegisDB: Decodable {
        let entries: [AegisEntry]
    }

    private struct AegisEntry: Decodable {
        let type: String
        let uuid: String?
        let name: String
        let issuer: String?
        let info: AegisEntryInfo
    }

    private struct AegisEntryInfo: Decodable {
        let secret: String
        let algo: String?
        let digits: Int?
        let period: Int?
    }
}
