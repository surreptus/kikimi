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

/// The look of the app: each section is a flat field of colour, text is near-black (or near-white in dark mode),
/// and the one action that matters on a screen is a solid pill. Colour marks where you are; nothing is decorative.
enum Theme {
    static let ink = Color(light: Color(hex: 0x121212), dark: Color(hex: 0xF4F1EA))
    /// Text on an `ink` face (the primary button).
    static let onInk = Color(light: .white, dark: Color(hex: 0x121212))
    static let muted = Color(light: Color(hex: 0x3F3F3F), dark: Color(hex: 0xD6D4CE))
    static let faint = Color(light: Color(hex: 0x4A4A4A), dark: Color(hex: 0xD3D1CB))
    /// Interactive tint for system controls.
    static let accent = ink

    /// Behind the floating nav, and behind sheets.
    static let page = Color(light: Color(hex: 0xF6F4EF), dark: Color(hex: 0x121212))
    /// The nav card.
    static let card = Color(light: .white, dark: Color(hex: 0x1F1F1F))
    /// A panel on a coloured field: translucent, so it works on every section colour.
    static let soft = Color(light: .white.opacity(0.62), dark: .white.opacity(0.09))
    static let softStrong = Color(light: .white.opacity(0.85), dark: .white.opacity(0.16))
    static let line = Color(light: .black.opacity(0.12), dark: .white.opacity(0.16))

    // The four section colours, light and dark.
    static let lilac = Color(light: Color(hex: 0xDCC8FA), dark: Color(hex: 0x3B2F5C))
    static let mint = Color(light: Color(hex: 0xBFEBD3), dark: Color(hex: 0x1F4A38))
    static let yellow = Color(light: Color(hex: 0xFFE14D), dark: Color(hex: 0x54460F))
    static let peach = Color(light: Color(hex: 0xFFB48A), dark: Color(hex: 0x5C3523))

    // Status and feedback. Always shown with a word as well, never as colour alone.
    static let red = Color(light: Color(hex: 0x9C1717), dark: Color(hex: 0xFFA8A0))
    static let green = Color(light: Color(hex: 0x1E8A55), dark: Color(hex: 0x6FD6A0))
    static let orange = Color(light: Color(hex: 0xB86E00), dark: Color(hex: 0xFFB84D))
    static let purple = Color(light: Color(hex: 0x7C4DDB), dark: Color(hex: 0xC3A6FF))

    static let cornerRadius: CGFloat = 20
    /// Inset of every screen's content from the window edge, so headings sit in the same place everywhere.
    static let screenPadding: CGFloat = 26

    /// How screens change: a short spring, or a plain quick fade when Reduce Motion is on.
    static func screenChange(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    /// Large headings are light; small ones need a little weight to stay readable.
    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: size >= 30 ? .regular : .semibold, design: .rounded) }
}

extension SidebarItem {
    /// The colour of this section's screen, and of its dot in the nav.
    var color: Color {
        switch self {
        case .importVideos: Theme.lilac
        case .words: Theme.mint
        case .review: Theme.yellow
        case .library: Theme.peach
        }
    }
}

// MARK: Buttons

/// A solid pill. Primary is the one action that matters (ink face); secondary is a quiet translucent pill.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }

    var kind: Kind = .primary
    var compact = false
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .medium, design: .rounded))
            .foregroundStyle(text)
            .padding(.vertical, compact ? 7 : 12)
            .padding(.horizontal, compact ? 14 : 26)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(face))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var face: Color {
        switch kind {
        case .primary: Theme.ink
        case .secondary: Theme.softStrong
        case .danger: Color(hex: 0xC62828)
        }
    }

    private var text: Color {
        switch kind {
        case .primary: Theme.onInk
        case .secondary: Theme.ink
        case .danger: .white
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { .init() }
    static func pill(_ kind: PillButtonStyle.Kind = .primary, compact: Bool = false, fullWidth: Bool = false) -> PillButtonStyle {
        .init(kind: kind, compact: compact, fullWidth: fullWidth)
    }
}

// MARK: Panels

/// Content that belongs together: flat, translucent, no outline. Buttons are solid; panels never are.
struct Panel: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.cornerRadius
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(highlighted ? Theme.softStrong : Theme.soft))
    }
}

extension View {
    func panel(padding: CGFloat = 16, radius: CGFloat = Theme.cornerRadius, highlighted: Bool = false) -> some View {
        modifier(Panel(padding: padding, radius: radius, highlighted: highlighted))
    }
}

// MARK: Progress

/// A thin line, like a lesson progress bar with nothing else on it.
struct ThinProgressStyle: ProgressViewStyle {
    var height: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let fraction = max(0, min(1, configuration.fractionCompleted ?? 0))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.15))
                Capsule().fill(Theme.ink)
                    .frame(width: max(height, proxy.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: height)
    }
}

extension ProgressViewStyle where Self == ThinProgressStyle {
    static var thin: ThinProgressStyle { .init() }
}

// MARK: Small pieces

/// A word-sized label. The colour tints the pill; the text stays ink so it reads on every section colour.
struct StatusPill: View {
    let text: String
    var color: Color?

    var body: some View {
        Text(text.prefix(1).uppercased() + text.dropFirst())
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(color.map { $0.opacity(0.35) } ?? Theme.softStrong))
            .foregroundStyle(Theme.ink)
    }
}

/// Section headline used across screens.
struct ScreenTitle: View {
    let text: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(Theme.title(34)).foregroundStyle(Theme.ink)
            // Always one subtitle line, so the heading is the same height on every screen.
            Text(subtitle ?? " ").font(.system(.callout, design: .rounded)).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }
}

/// Fades and nudges a screen vertically; used as the "inserted" state of a screen transition.
struct ScreenShift: ViewModifier {
    var y: CGFloat
    var opacity: Double

    func body(content: Content) -> some View { content.offset(y: y).opacity(opacity) }
}

/// The one character in the app: a flat flower with a small smile. Used only where something is finished or empty.
struct Blob: View {
    var color: Color = Theme.peach

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Circle().fill(color).frame(width: 30, height: 30).offset(y: -22).rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(color).frame(width: 52, height: 52)
            Circle().fill(Theme.ink).frame(width: 6, height: 6).offset(x: -9, y: -1)
            Circle().fill(Theme.ink).frame(width: 6, height: 6).offset(x: 9, y: -1)
            Circle().trim(from: 0.12, to: 0.38).stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14).rotationEffect(.degrees(30)).offset(y: 4)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }
}
