import Foundation

struct ParsedOTPAuth {
    let issuer: String?
    let label: String
    let secretBase32: String
    let algorithm: TOTPAlgorithm
    let digits: Int
    let period: TimeInterval
}

// RFC 6238 otpauth:// format: otpauth://totp/Label?secret=...&issuer=...&algorithm=SHA1&digits=6&period=30
enum OTPAuthParser {
    static func parse(_ uri: String) -> ParsedOTPAuth? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp" else {
            return nil
        }

        var rawPath = components.path
        if rawPath.hasPrefix("/") { rawPath.removeFirst() }
        let decodedLabel = rawPath.removingPercentEncoding ?? rawPath

        var labelIssuer: String?
        var label = decodedLabel
        if let colon = decodedLabel.firstIndex(of: ":") {
            labelIssuer = String(decodedLabel[..<colon]).trimmingCharacters(in: .whitespaces)
            label = String(decodedLabel[decodedLabel.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name.lowercased() == name })?.value }

        guard let secret = value("secret"), Base32.decode(secret) != nil else { return nil }
        let issuer = value("issuer") ?? labelIssuer
        let digits = Int(value("digits") ?? "") ?? 6
        let period = TimeInterval(value("period") ?? "") ?? 30
        let algo: TOTPAlgorithm = {
            switch (value("algorithm") ?? "SHA1").uppercased() {
            case "SHA256": return .sha256
            case "SHA512": return .sha512
            default: return .sha1
            }
        }()

        return ParsedOTPAuth(
            issuer: issuer,
            label: label,
            secretBase32: secret,
            algorithm: algo,
            digits: digits,
            period: period
        )
    }
}
