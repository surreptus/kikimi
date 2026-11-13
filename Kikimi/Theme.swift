import AppKit
import LangCore
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

/// The look of the app: a coloured window (green) around an off-white (or off-black) card; text is deep green (or
/// off-white in dark mode),
/// and the one action that matters on a screen is a solid pill. The accent is the ink; nothing is decorative.
enum Theme {
    static let ink = Color(light: Color(hex: 0x153A0B), dark: Color(hex: 0xF4F1EA))
    static let muted = Color(light: Color(hex: 0x183F0F), dark: Color(hex: 0xD6D4CE))
    static let faint = Color(light: Color(hex: 0x183F0F), dark: Color(hex: 0xD3D1CB))
    /// The accent is the ink itself: the main button, selected rows and the due badge are solid ink, so the only
    /// colour in the app is the field.
    static let accent = ink
    /// Text and icons on an `accent` face.
    static let onAccent = Color(light: .white, dark: Color(hex: 0x121212))

    /// The content card: a warm off-white (a touch of yellow-orange against the green window), and a very dark green of the window's hue, so text and tables sit on the calmest
    /// ground. The colour stays in the window around it (`chrome`) and the nav.
    static let card = Color(light: Color(hex: 0xFAF4E6), dark: Color(hex: 0x081611))
    /// A panel on the card: a faint tint of the ink, so it reads as a shape without a border.
    static let soft = Color(light: Color(hex: 0x153A0B).opacity(0.06), dark: .white.opacity(0.07))
    static let softStrong = Color(light: Color(hex: 0x153A0B).opacity(0.11), dark: .white.opacity(0.14))
    static let line = Color(light: .black.opacity(0.12), dark: .white.opacity(0.16))
    /// The shadow under a raised button: the ink colour in Light, black in Dark (where the ink is the light colour).
    static let raisedShadow = Color(light: Color(hex: 0x153A0B).opacity(0.22), dark: .black.opacity(0.45))
    /// The selected nav item, on the coloured window.
    static let navSelection = Color(light: .white.opacity(0.85), dark: .white.opacity(0.16))

    /// The colour of the whole window: a bright yellow-green, and a deep green in dark mode.
    static let field = Color(light: Color(hex: 0x66CC0A), dark: Color(hex: 0x124632))

    /// The window itself, behind the sidebar and around the content card: the field, a shade darker, so the card
    /// reads as a lighter shape on it.
    static let chrome = Color(light: Color(hex: 0x5DBA09), dark: Color(hex: 0x0C2D20))
    /// A selected table row: a soft tint, with ink text still on it.
    static let selection = Color(light: Color(hex: 0x153A0B).opacity(0.12), dark: .white.opacity(0.16))
    /// Alternate table rows: barely there.
    static let stripe = Color(light: .black.opacity(0.03), dark: .white.opacity(0.035))

    // Status and feedback. Always shown with a word as well, never as colour alone.
    static let red = Color(light: Color(hex: 0x801010), dark: Color(hex: 0xFFBDB5))
    static let green = Color(light: Color(hex: 0x197548), dark: Color(hex: 0x6FD6A0))
    static let orange = Color(light: Color(hex: 0x935800), dark: Color(hex: 0xFFB84D))
    static let purple = Color(light: Color(hex: 0x6F45C5), dark: Color(hex: 0xC3A6FF))

    /// The word a card is about, picked out in its sentence: a persimmon orange (4.7:1 on the Light card, 7.8:1 on the
    /// Dark one), always with bold as well, so colour is not the only signal.
    static let highlight = Color(light: Color(hex: 0xC4400F), dark: Color(hex: 0xFF8A5C))

    static let cornerRadius: CGFloat = 20
    /// Inset of every screen's content from the window edge, so headings sit in the same place everywhere.
    static let screenPadding: CGFloat = 26

    /// Every animation is this one curve, a cubic bezier that starts fast and settles gently, so movement feels
    /// responsive and never bounces.
    static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }

    /// How screens change: a short ease out, or a plain quick fade when Reduce Motion is on.
    static func screenChange(_ reduceMotion: Bool) -> Animation { easeOut(reduceMotion ? 0.12 : 0.35) }

    /// Captions and explanatory text: the body size of the app. Furigana over subtitle words is the one thing smaller (see `SubtitleRow`).
    static var small: Font { sized(size: 14, design: .rounded) }
    /// Reading copy: a modal's paragraphs and a page's subtitle. 16 pt, since 14 read as small.
    static var copy: Font { sized(size: 16, design: .rounded) }
    /// The pale yellow dot that says lessons are waiting. A new colour on purpose, so it stands apart from the due count.
    static let lessonDot = Color(light: Color(hex: 0xF2B705), dark: Color(hex: 0xFFD54A))

    /// Large headings are light; small ones need a little weight to stay readable.
    static func title(_ size: CGFloat = 24) -> Font { sized(size: size, weight: size >= 30 ? .regular : .semibold, design: .rounded) }

    /// A font of `size` points at the chosen text size (Settings > General). Every font in the app is made here or in
    /// `styled`, which is how the setting reaches all of it. Reading the scale in a view's body is what redraws the view
    /// when the setting changes.
    static func sized(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: TextScaleModel.shared.scale.scaled(Double(size)), weight: weight, design: design)
    }

    /// The system's text styles at the chosen size. macOS does not scale these itself, so each has its usual size here, and
    /// the smallest are raised to 12 pt, the least the app uses.
    static func styled(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        let (points, usual): (CGFloat, Font.Weight) = switch style {
        case .largeTitle: (26, .regular)
        case .title: (22, .regular)
        case .title2: (17, .regular)
        case .title3: (15, .regular)
        case .headline: (13, .bold)
        case .body: (13, .regular)
        case .callout: (12, .regular)
        default: (12, .regular)   // subheadline, footnote, caption: the system's 10 and 11 pt are below the least we use
        }
        return sized(size: points, weight: weight ?? usual, design: design)
    }
}

// MARK: Buttons

/// A solid pill. Primary is the one action that matters (ink face); secondary is a quiet translucent pill.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, inverted, quiet }

    var kind: Kind = .primary
    var compact = false
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .medium, design: .rounded))
            .foregroundStyle(text)
            .frame(minHeight: compact ? 16 : 20)   // text and icon pills of one size are the same height
            .padding(.vertical, compact ? 7 : 12)
            .padding(.horizontal, compact ? 14 : 26)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { background }
            .overlay { if kind == .quiet { Capsule().strokeBorder(Theme.line, lineWidth: 1) } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
            .animation(Theme.easeOut(0.08), value: configuration.isPressed)
    }

    /// The one button that does the main thing is slightly raised: lighter at the top, a bright edge inside it and a soft
    /// shadow. The others stay flat, so it is the only one that looks pressable at a glance. With Increase Contrast it is flat.
    @ViewBuilder private var background: some View {
        if kind == .primary, contrast == .standard {
            Capsule().fill(face)
                .overlay(Capsule().fill(LinearGradient(colors: shading, startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.6 : 0.40), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .shadow(color: Theme.raisedShadow.opacity(0.64), radius: 2, y: 1)
                .shadow(color: Theme.raisedShadow.opacity(0.45), radius: 5, y: 3)
        } else {
            Capsule().fill(face)
        }
    }

    /// A touch lighter at the top of the dark-green button; on the pale button in Dark, a hint of shade below. Kept faint: more reads as a bulb.
    private var shading: [Color] {
        scheme == .dark ? [.clear, .black.opacity(0.06)] : [.white.opacity(0.10), .clear]
    }

    private var face: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Theme.softStrong
        case .danger: Color(hex: 0xC62828)
        case .inverted: Theme.onAccent   // on a panel that is itself the accent colour
        case .quiet: .clear              // for an action done again and again, so it asks for little attention
        }
    }

    private var text: Color {
        switch kind {
        case .primary: Theme.onAccent
        case .secondary: Theme.ink
        case .danger: .white
        case .inverted: Theme.accent
        case .quiet: Theme.ink
        }
    }
}

/// An icon-only label in a fixed-width slot, so pills holding different symbols (a play arrow, a repeat sign) match.
struct PillIconStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon.frame(width: PillIconStyle.width)
    }
    static let width: CGFloat = 24
}

extension LabelStyle where Self == PillIconStyle {
    static var pillIcon: PillIconStyle { .init() }
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
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(highlighted ? Theme.softStrong : Theme.soft))
            // The faint tint is the whole edge; with Increase Contrast it is too weak to see, so a hairline draws it.
            .overlay { if contrast == .increased { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line, lineWidth: 1) } }
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
                        .animation(Theme.easeOut(0.25), value: fraction)
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
            Text(subtitle ?? " ").font(Theme.copy).foregroundStyle(Theme.muted).lineLimit(1)
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
    var color: Color = Mascot.paper

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

/// What the illustrations share: a body in the window's lime (Light) or an off-white (Dark), features in a deep
/// green (the app's own colour, not black), and a blush. White would vanish on the cream card.
private enum Mascot {
    static let face = Color(light: Color(hex: 0x153A0B), dark: Color(hex: 0x124632))
    static let paper = Color(light: Color(hex: 0x66CC0A), dark: Color(hex: 0xF4F1EA))
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
/// When something went wrong: what to do in plain words, with the technical message below for anyone reporting it.
struct FailureView: View {
    let title: LocalizedStringKey
    let problem: Problem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(title).font(Theme.title(22))
            Text(problem.message).multilineTextAlignment(.center).frame(maxWidth: 420)
            Text("Quit Kikimi and open it again. If it keeps happening, report it, and include the details. Reports are public, so leave out anything personal.")
                .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
            Link("Report a problem", destination: URL(string: "https://github.com/surreptus/kikimi/issues")!)
                .font(Theme.small)
            if !problem.detail.isEmpty { ProblemDetails(detail: problem.detail).frame(maxWidth: 480).padding(.top, 4) }
        }
        .padding(28)
    }
}

struct EmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var illustration: Illustration = .flower
    /// A button to the next step, so an empty page is never a dead end.
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                illustration.view
                Text(title).font(Theme.title(22)).foregroundStyle(Theme.ink)
                Text(message).font(Theme.styled(.body, design: .rounded)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.pill(compact: true)).padding(.top, 6)
            }
        }
        .padding(24)
    }
}

/// A quiet line of keys and what they do, such as "Space  Show answer". Wraps on a narrow window.
/// A key drawn as a small outlined cap, in the colour of the text around it so it reads on a dark or a light pill.
/// Hidden from VoiceOver: the button already has its name, and the keys are listed under Help > Keyboard Shortcuts.
struct KeyCap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(lineWidth: 1).opacity(0.55))
            .accessibilityHidden(true)
    }
}

/// A button's face with the key that presses it, so the key is learned where it is used.
struct KeyedLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let key: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            if let key { KeyCap(key) }
        }
    }
}

/// A row of keys under a card, each a button: it shows its key, does its action when clicked, and (for a bare letter) owns that
/// key, so what is shown is always what works.
struct ShortcutButtonRow: View {
    struct Item: Identifiable {
        let id: String
        let key: String
        let title: String
        var letter: Character?
        let perform: () -> Void
    }
    let items: [Item]

    var body: some View {
        FlowLayout {
            ForEach(items) { item in
                let button = Button(action: item.perform) {
                    HStack(spacing: 6) {
                        KeyCap(item.key)
                        Text(item.title).font(Theme.small).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(HintButtonStyle())
                .help("\(item.title) (\(item.key))")
                .accessibilityLabel(item.title)
                .accessibilityHint("Shortcut: \(item.key)")
                if let letter = item.letter { button.keyboardShortcut(KeyEquivalent(letter), modifiers: []) } else { button }
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
    }
}

/// A key hint that reads as a quiet label until the pointer is on it.
private struct HintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HintFace(configuration: configuration) }

    private struct HintFace: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? Theme.softStrong : hovering ? Theme.soft : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
                .animation(Theme.easeOut(0.12), value: hovering)
        }
    }
}

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
