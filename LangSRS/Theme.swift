import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// A colour that follows light/dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

/// The look of the app: bright, rounded, chunky, in pink.
enum Theme {
    static let pink = Color(light: Color(hex: 0xFF4FA1), dark: Color(hex: 0xFF5FAA))
    static let pinkEdge = Color(light: Color(hex: 0xD93A85), dark: Color(hex: 0xBF2F78))
    static let pinkSoft = Color(light: Color(hex: 0xFFE3F0), dark: Color(hex: 0x3D2030))
    static let pinkText = Color(light: Color(hex: 0xE0368A), dark: Color(hex: 0xFF7FBC))

    static let background = Color(light: Color(hex: 0xFFF1F8), dark: Color(hex: 0x170F15))
    static let card = Color(light: .white, dark: Color(hex: 0x241A21))
    static let line = Color(light: Color(hex: 0xF3D5E5), dark: Color(hex: 0x3B2B36))

    static let red = Color(hex: 0xFF4B4B)
    static let redEdge = Color(hex: 0xD93838)
    static let green = Color(hex: 0x58CC02)
    static let orange = Color(hex: 0xFF9600)
    static let purple = Color(hex: 0xCE82FF)

    static let cornerRadius: CGFloat = 20
    /// Inset of every screen's content from its card edge, so headings sit in the same place everywhere.
    static let screenPadding: CGFloat = 26

    /// How screens change: a short spring, or a plain quick fade when Reduce Motion is on.
    static func screenChange(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}

// MARK: Buttons

/// A Duolingo-style button: solid face, darker "ledge" underneath, and it sinks when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }

    var kind: Kind = .primary
    var compact = false
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = compact ? 3 : 4
        let radius: CGFloat = compact ? 11 : 15
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(text)
            .padding(.vertical, compact ? 7 : 12)
            .padding(.horizontal, compact ? 12 : 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: radius).fill(face))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: kind == .secondary ? 2 : 0))
            .background(RoundedRectangle(cornerRadius: radius).fill(edge).offset(y: pressed ? 0 : depth))
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.07), value: pressed)
    }

    private var face: Color {
        switch kind {
        case .primary: Theme.pink
        case .secondary: Theme.card
        case .danger: Theme.red
        }
    }

    private var edge: Color {
        switch kind {
        case .primary: Theme.pinkEdge
        case .secondary: Theme.line
        case .danger: Theme.redEdge
        }
    }

    private var border: Color { kind == .secondary ? Theme.line : .clear }

    private var text: Color {
        switch kind {
        case .primary, .danger: .white
        case .secondary: Theme.pinkText
        }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { .init() }
    static func chunky(_ kind: ChunkyButtonStyle.Kind = .primary, compact: Bool = false, fullWidth: Bool = false) -> ChunkyButtonStyle {
        .init(kind: kind, compact: compact, fullWidth: fullWidth)
    }
}

// MARK: Cards

struct DuoCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.cornerRadius
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(highlighted ? Theme.pinkSoft : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(highlighted ? Theme.pink : Theme.line, lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: radius).fill(highlighted ? Theme.pinkEdge : Theme.line).offset(y: 4))
            .padding(.bottom, 4)
    }
}

extension View {
    func duoCard(padding: CGFloat = 16, radius: CGFloat = Theme.cornerRadius, highlighted: Bool = false) -> some View {
        modifier(DuoCard(padding: padding, radius: radius, highlighted: highlighted))
    }
}

// MARK: Progress

/// A thick, rounded bar with a light sheen, like a lesson progress bar.
struct DuoProgressStyle: ProgressViewStyle {
    var height: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let fraction = max(0, min(1, configuration.fractionCompleted ?? 0))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.pink)
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.28)).frame(height: height * 0.28).padding(.horizontal, height * 0.4).padding(.top, height * 0.2)
                    }
                    .frame(width: max(height, proxy.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: height)
    }
}

extension ProgressViewStyle where Self == DuoProgressStyle {
    static var duo: DuoProgressStyle { .init() }
}

// MARK: Small pieces

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.4)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Section headline used across screens.
struct ScreenTitle: View {
    let text: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(Theme.title(26)).foregroundStyle(.primary)
            // Always one subtitle line, so the heading is the same height on every screen.
            Text(subtitle ?? " ").font(.system(.callout, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Fades and nudges a screen vertically; used as the "inserted" state of a screen transition.
struct ScreenShift: ViewModifier {
    var y: CGFloat
    var opacity: Double

    func body(content: Content) -> some View { content.offset(y: y).opacity(opacity) }
}
