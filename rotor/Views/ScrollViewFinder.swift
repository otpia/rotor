import AppKit
import SwiftUI

// 从 SwiftUI ScrollView 的子视图里反查 AppKit 的 NSScrollView，
// 用来在拖拽时实现连续、精确到像素的自动滚动
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
