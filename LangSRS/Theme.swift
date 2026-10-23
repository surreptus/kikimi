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

/// The look of the app: one flat field of colour (mint), text is near-black (or near-white in dark mode),
/// and the one action that matters on a screen is a solid pill. The accent is the ink; nothing is decorative.
enum Theme {
    static let ink = Color(light: Color(hex: 0x121212), dark: Color(hex: 0xF4F1EA))
    static let muted = Color(light: Color(hex: 0x3F3F3F), dark: Color(hex: 0xD6D4CE))
    static let faint = Color(light: Color(hex: 0x3F3F3F), dark: Color(hex: 0xD3D1CB))
    /// The accent is the ink itself: the main button, selected rows and the due badge are solid ink, so the only
    /// colour in the app is the field.
    static let accent = ink
    /// Text and icons on an `accent` face.
    static let onAccent = Color(light: .white, dark: Color(hex: 0x121212))

    /// Behind the floating nav, and behind sheets.
    static let page = Color(light: Color(hex: 0xF6F4EF), dark: Color(hex: 0x121212))
    /// The nav card.
    static let card = Color(light: .white, dark: Color(hex: 0x1F1F1F))
    /// A panel on a coloured field: translucent, so it works on every section colour.
    static let soft = Color(light: .white.opacity(0.62), dark: .white.opacity(0.09))
    static let softStrong = Color(light: .white.opacity(0.85), dark: .white.opacity(0.16))
    static let line = Color(light: .black.opacity(0.12), dark: .white.opacity(0.16))

    /// The colour of the whole window: a bright yellow-green, and a deep green in dark mode.
    static let field = Color(light: Color(hex: 0x66CC0A), dark: Color(hex: 0x124632))

    /// The side nav: a slightly darker strip of whatever colour the section is.
    static let rail = Color(light: .black.opacity(0.07), dark: .black.opacity(0.28))
    /// A selected table row: a soft lighter tint, with ink text still on it.
    static let selection = Color(light: .white.opacity(0.4), dark: .white.opacity(0.18))
    /// Alternate table rows: barely there.
    static let stripe = Color(light: .black.opacity(0.04), dark: .white.opacity(0.04))

    // Status and feedback. Always shown with a word as well, never as colour alone.
    static let red = Color(light: Color(hex: 0x801010), dark: Color(hex: 0xFFBDB5))
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

    /// The smallest text in the app. Furigana over subtitle words is the one exception (see `SubtitleRow`).
    static let small = Font.system(size: 12, design: .rounded)

    /// Large headings are light; small ones need a little weight to stay readable.
    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: size >= 30 ? .regular : .semibold, design: .rounded) }
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
        case .primary: Theme.accent
        case .secondary: Theme.softStrong
        case .danger: Color(hex: 0xC62828)
        }
    }

    private var text: Color {
        switch kind {
        case .primary: Theme.onAccent
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

/// A word-sized label. The pill is neutral so it reads on every section colour; a small dot carries the status
/// colour, and the word always says it too.
struct StatusPill: View {
    let text: String
    var color: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text.prefix(1).uppercased() + text.dropFirst())
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Capsule().fill(Theme.softStrong))
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
    /// Near-black in both modes: the flower is light in both, so the face must not follow the ink.
    private static let face = Color(hex: 0x121212)
    var color: Color = Color(light: .white, dark: Color(hex: 0xF4F1EA))

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Circle().fill(color).frame(width: 30, height: 30).offset(y: -22).rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(color).frame(width: 52, height: 52)
            Circle().fill(Self.face).frame(width: 6, height: 6).offset(x: -9, y: -1)
            Circle().fill(Self.face).frame(width: 6, height: 6).offset(x: 9, y: -1)
            Circle().trim(from: 0.12, to: 0.38).stroke(Self.face, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14).rotationEffect(.degrees(30)).offset(y: 4)
        }
        // One flat layer, so a fade applies to the whole flower; otherwise each overlapping circle fades on its own
        // and the seams show.
        .compositingGroup()
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }
}

/// What the illustrations share: a light body and a near-black face in both modes, so neither follows the ink.
private enum Mascot {
    static let face = Color(hex: 0x121212)
    static let paper = Color(light: .white, dark: Color(hex: 0xF4F1EA))
}

/// Two eyes and a small smile, centred `y` points from the middle.
private struct MascotFace: View {
    var y: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Mascot.face).frame(width: 6, height: 6).offset(x: -9, y: y)
            Circle().fill(Mascot.face).frame(width: 6, height: 6).offset(x: 9, y: y)
            Circle().trim(from: 0.12, to: 0.38).stroke(Mascot.face, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14).rotationEffect(.degrees(30)).offset(y: y + 7)
        }
    }
}

/// A clapperboard with a face: for an empty Videos page.
struct Clapperboard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Mascot.paper).frame(width: 66, height: 44).offset(y: 12)
            // The hinged top, with its stripes.
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Mascot.paper).frame(width: 70, height: 16)
                HStack(spacing: 7) {
                    ForEach(0..<4) { _ in Rectangle().fill(Mascot.face).frame(width: 7, height: 24).rotationEffect(.degrees(28)) }
                }
                .frame(width: 70, height: 16).clipShape(RoundedRectangle(cornerRadius: 5)).offset(x: -3)
            }
            .rotationEffect(.degrees(-9), anchor: .bottomLeading).offset(y: -18)
            MascotFace(y: 6)
        }
        .compositingGroup()   // one flat layer, so a fade doesn't show the overlaps
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A speech bubble with a face: for an empty Words page.
struct SpeechBubble: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(Mascot.paper).frame(width: 80, height: 58).offset(y: -4)
            BubbleTail().fill(Mascot.paper).frame(width: 18, height: 16).offset(x: -20, y: 30)
            MascotFace(y: -8)
        }
        .compositingGroup()
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }
}

/// Which character an empty state shows.
enum Illustration {
    case flower, clapperboard, bubble

    @ViewBuilder var view: some View {
        switch self {
        case .flower: Blob()
        case .clapperboard: Clapperboard()
        case .bubble: SpeechBubble()
        }
    }
}

/// Nothing here yet: a character, a title and one line saying what to do. Not for errors, which keep the warning icon.
struct EmptyState: View {
    let title: String
    let message: String
    var illustration: Illustration = .flower

    var body: some View {
        VStack(spacing: 10) {
            illustration.view
            Text(title).font(Theme.title(22)).foregroundStyle(Theme.ink)
            Text(message).font(.system(.body, design: .rounded)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
