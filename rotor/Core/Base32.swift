import Foundation

enum Base32 {
    private static let alphabet: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (i, ch) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".enumerated() {
            map[ch] = UInt8(i)
        }
        return map
    }()

    // RFC 4648 Base32 encoding; no `=` padding (TOTP secrets typically come without padding)
    static func encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var out = ""
        out.reserveCapacity((data.count * 8 + 4) / 5)
        var bits = 0
        var value = 0
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[(value >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            out.append(alphabet[(value << (5 - bits)) & 0x1F])
        }
        return out
    }

    // RFC 4648 Base32 decoding; tolerates case, spaces, and `=` padding
    static func decode(_ input: String) -> Data? {
        var bits = 0
        var value = 0
        var out = Data()
        for raw in input {
            let ch = Character(raw.uppercased())
            if ch == " " || ch == "=" || ch == "-" { continue }
            guard let v = alphabet[ch] else { return nil }
            value = (value << 5) | Int(v)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return out
    }
}
