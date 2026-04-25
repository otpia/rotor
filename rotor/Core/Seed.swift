import Foundation
import SwiftData

// Seed demo accounts on first launch; remove or guard with #if DEBUG before release
enum DemoSeed {
    struct Item {
        let issuer: String
        let label: String
        let iconSymbol: String
        let iconTintHex: String
        let secretBase32: String
    }

    static let items: [Item] = [
        Item(issuer: "Sony",    label: "liasicapsn@gmail.com",  iconSymbol: "s.circle.fill",       iconTintHex: "#111114", secretBase32: "JBSWY3DPEHPK3PXP"),
        Item(issuer: "Google",  label: "magicrolan@gmail.com",  iconSymbol: "g.circle.fill",       iconTintHex: "#EA4335", secretBase32: "JBSWY3DPEHPK3PXP"),
        Item(issuer: "Discord", label: "magicrolan@gmail.com",  iconSymbol: "gamecontroller.fill", iconTintHex: "#5865F2", secretBase32: "JBSWY3DPEHPK3PXP"),
        Item(issuer: "Aliyun",  label: "bijuzaixian",           iconSymbol: "cloud.fill",          iconTintHex: "#FF6600", secretBase32: "JBSWY3DPEHPK3PXP"),
        Item(issuer: "GitHub",  label: "joash@rarely.work",     iconSymbol: "chevron.left.forwardslash.chevron.right", iconTintHex: "#111114", secretBase32: "JBSWY3DPEHPK3PXP"),
    ]

    @MainActor
    static func seedIfEmpty(context: ModelContext) {
        var fd = FetchDescriptor<AccountModel>()
        fd.fetchLimit = 1
        let existing = (try? context.fetch(fd)) ?? []
        guard existing.isEmpty else { return }

        for (idx, item) in items.enumerated() {
            guard let secret = Base32.decode(item.secretBase32),
                  let ct = try? SecretVault.encrypt(secret) else { continue }
            let model = AccountModel(
                issuer: item.issuer,
                label: item.label,
                iconSymbol: item.iconSymbol,
                iconTintHex: item.iconTintHex,
                sortOrder: idx,
                ciphertext: ct
            )
            context.insert(model)
        }
        try? context.save()
    }
}
