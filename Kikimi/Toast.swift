import SwiftUI

/// A short message about something that just happened, shown over the window and gone a few seconds later.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    /// A button on the toast, such as Undo.
    var action: (title: String, run: () -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Sits at the top centre of the window, out of the way of the buttons along the bottom. It goes by itself; pointing at it
/// holds it, and it can be closed.
struct ToastHost: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = app.toast {
                HStack(spacing: 10) {
                    if toast.isError {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red).accessibilityHidden(true)
                    }
                    Text(toast.text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if let action = toast.action {
                        Button(action.title) { action.run(); app.dismissToast() }
                            .buttonStyle(.plain).fontWeight(.bold).underline()
                    }
                    Button { app.dismissToast() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted)
                        .accessibilityLabel("Dismiss")
                        .help("Dismiss")
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                .frame(maxWidth: 520)
                .padding(.top, 14)
                .onHover { app.holdToast($0) }
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Theme.easeOut(0.2), value: app.toast)
        .allowsHitTesting(app.toast != nil)
    }
}
