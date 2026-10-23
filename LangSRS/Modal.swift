import SwiftUI

private struct DismissModalKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the modal this view is shown in. Views inside `.modal` call this instead of `dismiss`.
    var dismissModal: () -> Void {
        get { self[DismissModalKey.self] }
        set { self[DismissModalKey.self] = newValue }
    }
}

/// A modal panel over the window. Unlike a system sheet, a click outside it (or Escape) closes it.
private struct ModalModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel
    @FocusState private var focused: Bool

    private func close() { isPresented = false }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture(perform: close)
                            .accessibilityHidden(true)
                        panel()
                            .environment(\.dismissModal, close)
                            .background(Theme.page)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
                            .focusable()
                            .focused($focused)
                            .focusEffectDisabled()
                            .onKeyPress(.escape) { close(); return .handled }
                            .onAppear { focused = true }
                            .accessibilityAddTraits(.isModal)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isPresented)
    }
}

extension View {
    func modal<Panel: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(ModalModifier(isPresented: isPresented, panel: content))
    }
}
