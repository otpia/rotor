import AppKit
import SwiftUI

// Reach the NSWindow backing a SwiftUI Scene to configure AppKit properties like level and behavior
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
    }
}
