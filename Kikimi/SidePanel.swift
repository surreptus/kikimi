import SwiftUI

/// A panel beside a page, as on Words and Review: a hairline, a fixed width, and a slide in that becomes a fade with
/// Reduce Motion.
private struct SidePanel<Panel: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder let panel: () -> Panel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            if isPresented {
                Rectangle().fill(Theme.line).frame(width: 1)
                panel()
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPresented)
    }
}

extension View {
    func sidePanel<Panel: View>(isPresented: Bool, @ViewBuilder panel: @escaping () -> Panel) -> some View {
        modifier(SidePanel(isPresented: isPresented, panel: panel))
    }
}
