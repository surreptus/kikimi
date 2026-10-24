import AppKit
import SwiftUI

/// Reports where its view is, in window coordinates (origin at the bottom left, the same as a mouse event's
/// `locationInWindow`), so a click can be tested against it. Put it in a view's `.background`.
struct WindowFrameReader: NSViewRepresentable {
    var onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> FrameView {
        let view = FrameView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: FrameView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class FrameView: NSView {
        var onChange: ((CGRect) -> Void)?
        private var last: CGRect = .null

        override func layout() { super.layout(); report() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }

        func report() {
            guard window != nil else { return }
            let frame = convert(bounds, to: nil)
            guard frame != last else { return }
            last = frame
            // Not during a SwiftUI update: the callback sets state.
            DispatchQueue.main.async { [weak self] in self?.onChange?(frame) }
        }
    }
}
