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
    static let ink = Color(light: Color(hex: 0x153A0B), dark: Color(hex: 0xF4F1EA))
    static let muted = Color(light: Color(hex: 0x1C4612), dark: Color(hex: 0xD6D4CE))
    static let faint = Color(light: Color(hex: 0x1C4612), dark: Color(hex: 0xD3D1CB))
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

    /// The window itself, behind the sidebar and around the content card: the field, a shade darker, so the card
    /// reads as a lighter shape on it.
    static let chrome = Color(light: Color(hex: 0x5DBA09), dark: Color(hex: 0x0C2D20))
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
        if let value = configuration.fractionCompleted {
            let fraction = max(0, min(1, value))
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
        } else {
            IndeterminateBar(height: height)
        }
    }
}

/// For work with no measurable progress: a short segment that slides back and forth along the track. With Reduce
/// Motion on it stays still at the start, so something is shown without anything moving.
private struct IndeterminateBar: View {
    let height: CGFloat
    @State private var atEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let segment = proxy.size.width * 0.28
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.15))
                Capsule().fill(Theme.ink)
                    .frame(width: segment)
                    .offset(x: atEnd ? proxy.size.width - segment : 0)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { atEnd = true }
        }
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
            Text(text)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Capsule().fill(Theme.softStrong))
        .foregroundStyle(Theme.ink)
    }
}

/// Section headline used across screens.
struct ScreenTitle: View {
    let text: LocalizedStringKey
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
    var color: Color = Color(light: .white, dark: Color(hex: 0xF4F1EA))

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Circle().fill(color).frame(width: 30, height: 30).offset(y: -22).rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(color).frame(width: 52, height: 52)
            MascotFace(y: -2, mood: .content)
        }
        // One flat layer, so a fade applies to the whole flower; otherwise each overlapping circle fades on its own
        // and the seams show.
        .compositingGroup()
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }
}

/// What the illustrations share: a light body, features in a deep green (the app's own colour, not black), and a
/// blush. None of them follows the ink, so they look the same in both modes.
private enum Mascot {
    static let face = Color(light: Color(hex: 0x1E5A0B), dark: Color(hex: 0x124632))
    static let paper = Color(light: .white, dark: Color(hex: 0xF4F1EA))
    static let blush = Color(hex: 0xFF8FA3).opacity(0.75)
}

/// How a character looks: each empty state has its own, so they aren't one face repeated.
private enum Mood {
    case smile      // two dots and a small smile
    case content    // eyes closed, happy: at rest after finishing
    case grin       // wide eyes, open smile: eager, for something about to start
    case chatty     // a small round mouth: about to say something
}

/// A face, centred `y` points from the middle.
private struct MascotFace: View {
    var y: CGFloat
    var mood: Mood = .smile

    var body: some View {
        ZStack {
            Circle().fill(Mascot.blush).frame(width: 8, height: 8).offset(x: -17, y: y + 6)
            Circle().fill(Mascot.blush).frame(width: 8, height: 8).offset(x: 17, y: y + 6)
            eyes
            mouth
        }
    }

    @ViewBuilder private var eyes: some View {
        switch mood {
        case .content:
            // Closed, happy arches.
            ForEach([-9.0, 9.0], id: \.self) { x in
                Circle().trim(from: 0.5, to: 1).stroke(Mascot.face, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 8, height: 8).offset(x: x, y: y + 2)
            }
        default:
            let size: CGFloat = mood == .grin ? 7.5 : 6
            Circle().fill(Mascot.face).frame(width: size, height: size).offset(x: -9, y: y)
            Circle().fill(Mascot.face).frame(width: size, height: size).offset(x: 9, y: y)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .smile, .content:
            Circle().trim(from: 0.12, to: 0.38).stroke(Mascot.face, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14).rotationEffect(.degrees(30)).offset(y: y + 7)
        case .grin:
            Circle().trim(from: 0, to: 0.5).fill(Mascot.face).frame(width: 14, height: 14).offset(y: y + 5)
        case .chatty:
            Circle().strokeBorder(Mascot.face, lineWidth: 2).frame(width: 8, height: 8).offset(y: y + 9)
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
            MascotFace(y: 6, mood: .grin)
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
            MascotFace(y: -8, mood: .chatty)
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
    let title: LocalizedStringKey
    let message: LocalizedStringKey
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

/// A quiet line of keys and what they do, such as "Space  Show answer". Wraps on a narrow window.
struct ShortcutHints: View {
    let items: [(key: String, action: String)]

    var body: some View {
        FlowLayout {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(item.key)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.softStrong))
                    Text(item.action).font(Theme.small).foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 14)
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard shortcuts: " + items.map { "\($0.key) \($0.action)" }.joined(separator: ", "))
    }
}
