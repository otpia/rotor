import CryptoKit
import Foundation

enum TOTPAlgorithm: String, Hashable {
    case sha1, sha256, sha512
}

struct TOTPGenerator: Hashable {
    let secret: Data
    let digits: Int
    let period: TimeInterval
    let algorithm: TOTPAlgorithm

    init(secret: Data, digits: Int = 6, period: TimeInterval = 30, algorithm: TOTPAlgorithm = .sha1) {
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
    }

    // RFC 6238: HOTP driven by a time-based counter
    func code(at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / period)
        var counterBE = counter.bigEndian
        let counterData = withUnsafeBytes(of: &counterBE) { Data($0) }
        let key = SymmetricKey(data: secret)

        let mac: Data
        switch algorithm {
        case .sha1:
            mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            mac = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            mac = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated =
            (UInt32(mac[offset] & 0x7F) << 24) |
            (UInt32(mac[offset + 1]) << 16) |
            (UInt32(mac[offset + 2]) << 8) |
             UInt32(mac[offset + 3])
        let mod = UInt32(pow(10.0, Double(digits)))
        let value = truncated % mod
        return String(format: "%0\(digits)d", value)
    }

    // Seconds remaining in the current period
    func secondsRemaining(at date: Date = Date()) -> TimeInterval {
        let t = date.timeIntervalSince1970
        return period - t.truncatingRemainder(dividingBy: period)
    }
}
