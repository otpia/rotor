import AppKit
import CryptoKit
import Foundation

// Try to clear the pasteboard 60 seconds after copy; before clearing, compare changeCount + SHA-256 hash
// to avoid overwriting anything else the user copied during that 60s window
@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    private var clearTimer: Timer?
    private var lastChangeCount: Int = 0
    private var lastHash: Data = Data()

    private init() {}

    func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        lastChangeCount = pb.changeCount
        lastHash = hash(of: string)
        scheduleClear()
    }

    private func scheduleClear() {
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.clearIfUnchanged() }
        }
    }

    private func clearIfUnchanged() {
        let pb = NSPasteboard.general
        guard pb.changeCount == lastChangeCount else { return }
        if let current = pb.string(forType: .string), hash(of: current) != lastHash {
            return
        }
        pb.clearContents()
    }

    private func hash(of string: String) -> Data {
        Data(SHA256.hash(data: Data(string.utf8)))
    }
}
