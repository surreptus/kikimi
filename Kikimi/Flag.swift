import SwiftUI

/// A simplified flag, drawn rather than shipped as an image: flat stripes and one disc, no crests. It is decoration;
/// the language's name always sits beside it.
struct Flag: View {
    let region: String

    var body: some View {
        stripes
            .frame(width: 36, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stripes: some View {
        switch region {
        case "ES": bands([(0xAA151B, 1), (0xF1BF00, 2), (0xAA151B, 1)], vertical: false)
        case "FR": bands([(0x002395, 1), (0xFFFFFF, 1), (0xED2939, 1)], vertical: true)
        case "DE": bands([(0x000000, 1), (0xDD0000, 1), (0xFFCE00, 1)], vertical: false)
        case "JP": ZStack { Color.white; Circle().fill(Color(hex: 0xBC002D)).frame(width: 14, height: 14) }
        default: Color.clear
        }
    }

    /// Bands in proportion to their weights, side by side or stacked.
    private func bands(_ parts: [(UInt32, CGFloat)], vertical: Bool) -> some View {
        GeometryReader { proxy in
            let total = parts.reduce(0) { $0 + $1.1 }
            let layout = vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Color(hex: part.0).frame(
                        width: vertical ? proxy.size.width * part.1 / total : nil,
                        height: vertical ? nil : proxy.size.height * part.1 / total)
                }
            }
        }
    }
}
