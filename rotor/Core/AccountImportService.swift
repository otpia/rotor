import Foundation
import SwiftData

// Unified batch import pipeline shared by .rotor files / QR images / pasted URIs
// Dedupe key: issuer + label + secret, all lowercased/normalized
@MainActor
enum AccountImportService {
    struct Candidate {
        var id: UUID?
        var issuer: String?
        var label: String
        var secretBase32: String
        var digits: Int
        var period: TimeInterval
        var algorithm: TOTPAlgorithm
        var iconSymbol: String?
        var iconTintHex: String?
        var sortOrder: Int?
        var createdAt: Date?
    }

    struct Progress: Equatable {
        var current: Int
        var total: Int
        var stage: String
    }

    struct Outcome: Equatable {
        var inserted: Int
        var skipped: Int
        var failed: Int
    }

    static func performImport(
        items: [Candidate],
        into context: ModelContext,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws -> Outcome {
        progress(Progress(current: 0, total: items.count, stage: "正在扫描已有账户…"))

        // Decrypt existing accounts' secrets once to build the dedupe set
        let existing = (try? context.fetch(FetchDescriptor<AccountModel>())) ?? []
        var seenKeys = Set<String>()
        for account in existing {
            if let secret = try? SecretVault.decrypt(account.ciphertext) {
                seenKeys.insert(dedupeKey(issuer: account.issuer, label: account.label, secret: secret))
            }
        }
        var nextOrder = existing.count

        var inserted = 0
        var skipped = 0
        var failed = 0

        for (index, item) in items.enumerated() {
            progress(Progress(
                current: index,
                total: items.count,
                stage: "正在导入 \(index + 1) / \(items.count)"
            ))

            guard let secret = Base32.decode(item.secretBase32) else {
                failed += 1
                continue
            }
            let key = dedupeKey(issuer: item.issuer ?? "", label: item.label, secret: secret)
            if seenKeys.contains(key) {
                skipped += 1
                continue
            }

            do {
                let ciphertext = try SecretVault.encrypt(secret)
                let model = AccountModel(
                    id: item.id ?? UUID(),
                    issuer: (item.issuer?.isEmpty == false ? item.issuer! : item.label),
                    label: item.label,
                    digits: item.digits,
                    period: item.period,
                    algorithm: item.algorithm,
                    iconSymbol: item.iconSymbol ?? "globe",
                    iconTintHex: item.iconTintHex ?? "#2F6FFF",
                    sortOrder: item.sortOrder ?? nextOrder,
                    createdAt: item.createdAt ?? Date(),
                    ciphertext: ciphertext
                )
                context.insert(model)
                seenKeys.insert(key)
                nextOrder += 1
                inserted += 1
            } catch {
                failed += 1
            }

            // Yield a frame so the progress bar can refresh (without yielding the UI freezes until the loop ends)
            await Task.yield()
        }

        progress(Progress(current: items.count, total: items.count, stage: "正在保存…"))
        try context.save()
        progress(Progress(current: items.count, total: items.count, stage: "完成"))

        return Outcome(inserted: inserted, skipped: skipped, failed: failed)
    }

    private static func dedupeKey(issuer: String, label: String, secret: Data) -> String {
        let i = issuer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(i)|\(l)|\(secret.base64EncodedString())"
    }
}
