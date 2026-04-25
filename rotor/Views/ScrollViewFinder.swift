import AppKit
import SwiftUI

// Walk up from a SwiftUI ScrollView descendant to find the underlying AppKit NSScrollView,
// enabling continuous, pixel-accurate auto-scroll while dragging
struct ScrollViewFinder: NSViewRepresentable {
    @Binding var scrollView: NSScrollView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            scrollView = locate(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if scrollView == nil {
            DispatchQueue.main.async { [weak nsView] in
                scrollView = locate(from: nsView)
            }
        }
    }

    private func locate(from view: NSView?) -> NSScrollView? {
        var current = view?.superview
        while current != nil {
            if let sv = current as? NSScrollView { return sv }
            current = current?.superview
        }
        return nil
    }
}
