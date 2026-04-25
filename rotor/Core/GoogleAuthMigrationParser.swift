import Foundation

// Google Authenticator migration format: otpauth-migration://offline?data=<url-encoded-base64>
// `data` is protobuf; schema is documented in CLAUDE.md §4.5
struct GoogleAuthMigrationItem {
    let issuer: String?
    let label: String
    let secret: Data            // raw bytes (not Base32-encoded)
    let digits: Int
    let period: TimeInterval
    let algorithm: TOTPAlgorithm
}

enum GoogleAuthMigrationParser {
    static func isMigrationURI(_ uri: String) -> Bool {
        uri.lowercased().hasPrefix("otpauth-migration://")
    }

    static func parse(_ uri: String) -> [GoogleAuthMigrationItem]? {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth-migration",
              components.host?.lowercased() == "offline" else {
            return nil
        }
        guard let base64 = components.queryItems?
                .first(where: { $0.name == "data" })?.value else {
            return nil
        }
        guard let raw = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        return parsePayload(raw)
    }

    static func parsePayload(_ data: Data) -> [GoogleAuthMigrationItem]? {
        guard let fields = Protobuf.parse(data) else { return nil }
        var items: [GoogleAuthMigrationItem] = []
        for field in fields where field.number == 1 {
            guard case .bytes(let sub) = field.value else { continue }
            if let item = parseParameters(sub) {
                items.append(item)
            }
        }
        return items
    }

    private static func parseParameters(_ data: Data) -> GoogleAuthMigrationItem? {
        guard let fields = Protobuf.parse(data) else { return nil }
        var secret = Data()
        var name = ""
        var issuer: String?
        var algorithm: TOTPAlgorithm = .sha1
        var digits = 6
        var otpType = 2 // default to TOTP

        for f in fields {
            switch f.number {
            case 1:
                if case .bytes(let d) = f.value { secret = d }
            case 2:
                if case .bytes(let d) = f.value, let s = String(data: d, encoding: .utf8) {
                    name = s
                }
            case 3:
                if case .bytes(let d) = f.value,
                   let s = String(data: d, encoding: .utf8),
                   !s.isEmpty {
                    issuer = s
                }
            case 4:
                if case .varint(let v) = f.value {
                    switch v {
                    case 2: algorithm = .sha256
                    case 3: algorithm = .sha512
                    default: algorithm = .sha1
                    }
                }
            case 5:
                if case .varint(let v) = f.value {
                    digits = (v == 2) ? 8 : 6
                }
            case 6:
                if case .varint(let v) = f.value {
                    otpType = Int(v)
                }
            default:
                continue
            }
        }

        guard otpType == 2 else { return nil } // HOTP not supported yet
        guard !secret.isEmpty else { return nil }

        // GA's `name` field is often "Issuer:user@example.com"; if `issuer` isn't provided, split it out of `name`
        var label = name
        if issuer == nil, let colon = name.firstIndex(of: ":") {
            issuer = String(name[..<colon]).trimmingCharacters(in: .whitespaces)
            label = String(name[name.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }

        return GoogleAuthMigrationItem(
            issuer: issuer,
            label: label,
            secret: secret,
            digits: digits,
            period: 30,
            algorithm: algorithm
        )
    }
}
