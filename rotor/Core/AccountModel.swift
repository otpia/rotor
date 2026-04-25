import Foundation
import SwiftData
import SwiftUI

@Model
final class AccountModel {
    @Attribute(.unique) var id: UUID
    var issuer: String
    var label: String
    var digits: Int
    var period: TimeInterval
    var algorithmRaw: String
    var iconSymbol: String
    var iconTintHex: String
    var sortOrder: Int
    var createdAt: Date
    // Optional group tag; UI sections by `group`; empty string means ungrouped
    var group: String = ""
    // TOTP secret ciphertext: AES-GCM combined (nonce + ciphertext + tag); see VaultKey for the master key
    var ciphertext: Data

    init(
        id: UUID = UUID(),
        issuer: String,
        label: String,
        digits: Int = 6,
        period: TimeInterval = 30,
        algorithm: TOTPAlgorithm = .sha1,
        iconSymbol: String = "globe",
        iconTintHex: String = "#2F6FFF",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        group: String = "",
        ciphertext: Data = Data()
    ) {
        self.id = id
        self.issuer = issuer
        self.label = label
        self.digits = digits
        self.period = period
        self.algorithmRaw = algorithm.rawValue
        self.iconSymbol = iconSymbol
        self.iconTintHex = iconTintHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.group = group
        self.ciphertext = ciphertext
    }

    var algorithm: TOTPAlgorithm {
        get { TOTPAlgorithm(rawValue: algorithmRaw) ?? .sha1 }
        set { algorithmRaw = newValue.rawValue }
    }

    var iconTint: Color {
        Color(hex: iconTintHex) ?? .rotorPrimary
    }

    // Decrypt the ciphertext to obtain the TOTP secret and build a one-shot generator; returns nil if decryption fails or the vault is locked
    @MainActor
    func makeGenerator() -> TOTPGenerator? {
        guard !ciphertext.isEmpty,
              let secret = try? SecretVault.decrypt(ciphertext) else { return nil }
        return TOTPGenerator(secret: secret, digits: digits, period: period, algorithm: algorithm)
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
