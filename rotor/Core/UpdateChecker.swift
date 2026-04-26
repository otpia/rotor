import AppKit
import Foundation
import Observation

// Lightweight GitHub Releases-based update check.
// We deliberately do not auto-replace the running .app: the project ships with
// ad-hoc signed DMGs (no Developer ID notarization), so Gatekeeper would block
// any silent in-place replacement. Users drag the new build into /Applications
// like any other un-notarized macOS app.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case error(String)
    }

    struct Release: Equatable, Identifiable {
        let tag: String           // e.g. "v1.0.5"
        let version: String       // tag without leading "v", e.g. "1.0.5"
        let name: String
        let body: String
        let publishedAt: Date?
        let dmgURL: URL?
        let htmlURL: URL

        var id: String { tag }
    }

    private(set) var state: State = .idle
    // When non-nil, a SwiftUI .sheet binding shows UpdateAvailableSheet.
    // Set by manual checks unconditionally; set by silent auto-checks only when
    // the release isn't on the user's "skipped" list.
    var pendingPrompt: Release?

    private let owner = "otpia"
    private let repo  = "rotor"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func check(silent: Bool) async {
        if case .checking = state { return }
        state = .checking
        do {
            let release = try await fetchLatest()
            if Self.compare(release.version, currentVersion) > 0 {
                state = .available(release)
                let skipped = SettingsStore.shared.skippedUpdateVersion
                if !silent || release.version != skipped {
                    pendingPrompt = release
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func download(_ release: Release) async throws -> URL {
        guard let dmgURL = release.dmgURL else {
            throw NSError(domain: "Rotor.Update", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "该版本未提供 DMG 资产"])
        }
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
            .appendingPathComponent("Rotor", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent("Rotor-\(release.version).dmg")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let (tempURL, response) = try await URLSession.shared.download(from: dmgURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "Rotor.Update", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "下载失败：HTTP \(http.statusCode)"])
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private func fetchLatest() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw NSError(domain: "Rotor.Update", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "URL 构造失败"])
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Rotor/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Rotor.Update", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "Rotor.Update", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub API 返回 \(http.statusCode)"])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let api = try decoder.decode(APIRelease.self, from: data)
        let dmg = api.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
        return Release(
            tag: api.tag_name,
            version: api.tag_name.hasPrefix("v") ? String(api.tag_name.dropFirst()) : api.tag_name,
            name: api.name ?? api.tag_name,
            body: api.body ?? "",
            publishedAt: api.published_at,
            dmgURL: dmg.flatMap { URL(string: $0.browser_download_url) },
            htmlURL: URL(string: api.html_url) ?? URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
        )
    }

    // Numeric semver compare; non-numeric suffixes are dropped to keep the check robust
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
        }
        let pa = parts(a)
        let pb = parts(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private struct APIRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let published_at: Date?
        let html_url: String
        let assets: [APIAsset]
    }
    private struct APIAsset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
