import SwiftUI

/// A short message about something that just happened, shown over the window and gone a few seconds later.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    /// The raw text of an error, shown when the learner asks for it.
    var detail: String?
    /// A button on the toast, such as Undo.
    var action: (title: String, run: () -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Sits at the top centre of the window, out of the way of the buttons along the bottom. It goes by itself; pointing at it
/// holds it, and it can be closed.
struct ToastHost: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetail = false

    var body: some View {
        ZStack {
            if let toast = app.toast {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if toast.isError {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red).accessibilityHidden(true)
                        }
                        Text(toast.text).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                        if let action = toast.action {
                            Button(action.title) { action.run(); app.dismissToast() }
                                .buttonStyle(.plain).fontWeight(.bold).underline()
                        }
                        if toast.detail != nil {
                            Button(showingDetail ? "Hide details" : "Show details") {
                                showingDetail.toggle()
                                app.holdToast(showingDetail)   // it stays up while the details are open
                            }
                            .buttonStyle(.plain).fontWeight(.bold).underline()
                        }
                        Button { app.dismissToast() } label: { Image(systemName: "xmark").font(Theme.sized(size: 11, weight: .semibold)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted)
                            .accessibilityLabel("Dismiss")
                            .help("Dismiss")
                    }
                    if showingDetail, let detail = toast.detail {
                        Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(Theme.sized(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                .frame(maxWidth: 520)
                .padding(.top, 14)
                .onHover { if !showingDetail { app.holdToast($0) } }
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Theme.easeOut(0.2), value: app.toast)
        .allowsHitTesting(app.toast != nil)
    }
}
