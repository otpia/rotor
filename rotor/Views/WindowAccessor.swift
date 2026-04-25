import AppKit
import SwiftUI

// Apply AppKit window-level properties (level + sharingType) reactively.
// Pass values from the SwiftUI body so @Observable tracking re-runs body
// on settings changes and the values get re-applied immediately.
struct WindowAccessor: NSViewRepresentable {
    var level: NSWindow.Level? = nil
    var sharingType: NSWindow.SharingType? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(view: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(view: view)
    }

    private func apply(view: NSView) {
        let level = self.level
        let sharingType = self.sharingType
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if let level { window.level = level }
            if let sharingType { window.sharingType = sharingType }
        }
    }
}
