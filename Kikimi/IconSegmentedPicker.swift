import SwiftUI

/// A row of choices, each with an icon and a short name, one of them selected. The system segmented control on macOS
/// shows only the names, so this draws its own; it behaves as one for VoiceOver (each is a selectable button with its
/// full name) and the chosen one is bold as well as filled, so colour is not the only sign.
struct IconSegmentedPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        /// A word or two, shown beside the icon.
        let title: String
        /// What VoiceOver says.
        let fullTitle: String
        let symbol: String
    }

    let options: [Option]
    @Binding var selection: Value
    @Namespace private var chosen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { segment($0) }
        }
        .padding(3)
        .background(Capsule().fill(Theme.ink.opacity(0.08)))
        // The highlight slides to the new choice and the labels change weight with it.
        .animation(reduceMotion ? nil : Theme.easeOut(0.2), value: selection)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.value == selection
        return Button { selection = option.value } label: {
            Label(option.title, systemImage: option.symbol)
                .labelStyle(.titleAndIcon)
                .font(Theme.sized(size: 13, weight: selected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
                .background {
                    if selected {
                        Capsule().fill(Theme.card)
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                            .matchedGeometryEffect(id: "selection", in: chosen)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(option.fullTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
