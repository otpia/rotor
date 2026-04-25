import AppKit
import SwiftUI

// 拿到 SwiftUI Scene 背后的 NSWindow，用来配置 level、behavior 等 AppKit 属性
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
