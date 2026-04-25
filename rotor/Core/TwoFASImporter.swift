import Foundation

enum TwoFASImportError: LocalizedError {
    case invalidFormat
    case encryptedNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidFormat:         return "不是有效的 2FAS 备份 JSON"
        case .encryptedNotSupported: return "此 2FAS 备份已加密，暂不支持；请先在 2FAS 中导出未加密备份"
        }
    }
}

// 2FAS schema ref: https://github.com/twofas/2fas-ios backups
enum TwoFASImporter {
    static func parse(_ data: Data) throws -> [AccountImportService.Candidate] {
        let decoder = JSONDecoder()
        guard let backup = try? decoder.decode(TwoFASBackup.self, from: data) else {
            throw TwoFASImportError.invalidFormat
        }
        if let encrypted = backup.servicesEncrypted, !encrypted.isEmpty {
            throw TwoFASImportError.encryptedNotSupported
        }
        guard let services = backup.services else { return [] }
        return services.compactMap(toCandidate)
    }

    private static func toCandidate(_ service: TwoFASService) -> AccountImportService.Candidate? {
        // Resolve fields from multiple locations: older versions had secret at service level, newer ones use otp.secret
        let secret = service.secret ?? service.otp?.secret
        guard let secretBase32 = secret, !secretBase32.isEmpty else { return nil }

        let tokenType = (service.otp?.tokenType ?? service.tokenType ?? "TOTP").uppercased()
        guard tokenType == "TOTP" else { return nil }

        let algo: TOTPAlgorithm
        switch (service.otp?.algorithm ?? "SHA1").uppercased() {
        case "SHA256": algo = .sha256
        case "SHA512": algo = .sha512
        default:       algo = .sha1
        }

        let issuer = [service.otp?.issuer, service.name]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let label = [service.otp?.account, service.otp?.label, service.name]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? ""

        return AccountImportService.Candidate(
            issuer: issuer,
            label: label,
            secretBase32: secretBase32,
            digits: service.otp?.digits ?? 6,
            period: TimeInterval(service.otp?.period ?? 30),
            algorithm: algo
        )
    }

    private struct TwoFASBackup: Decodable {
        let services: [TwoFASService]?
        let servicesEncrypted: String?
        let schemaVersion: Int?
    }

    private struct TwoFASService: Decodable {
        let name: String?
        let secret: String?
        let otp: TwoFASOTP?
        let tokenType: String?
    }

    private struct TwoFASOTP: Decodable {
        let issuer: String?
        let label: String?
        let account: String?
        let secret: String?
        let algorithm: String?
        let digits: Int?
        let period: Int?
        let tokenType: String?
    }
}
