import LangCore
import SwiftUI

/// One subtitle line. Hover (or focus) a word to see its meaning in the hint bar; click it, or press Return on it,
/// to pin that meaning. Hovering or focusing the line shows furigana above Japanese words.
///
/// Keyboard: click a line (or Tab to it with Full Keyboard Access) to focus it; ← → move between its words,
/// Return pins the word, Esc unpins, ↑ ↓ move to the previous or next line.
struct SubtitleRow: View {
    let line: Subtitle
    let index: Int
    let active: Bool
    let profile: (any LanguageProfile)?
    /// Empty when highlighting is off.
    let statuses: [WordKey: WordStatus]
    @Binding var hovered: Token?
    @Binding var pinned: Token?
    var focusedLine: FocusState<Int?>.Binding
    let moveFocus: (Int) -> Void
    let seek: () -> Void
    let exportAudio: () -> Void
    let exportVideo: () -> Void
    let edit: () -> Void

    @AppStorage(TranscriptSize.key) private var size = TranscriptSize.standard
    @State private var segments: [LineSegment] = []
    @State private var rowHovered = false
    @State private var hoveredChunk: Int?
    /// Which word of this line the keyboard is on (an index into `contentChunks`).
    @State private var caret = 0

    struct Chunk: Identifiable {
        let id: Int
        let token: Token?
        let text: String
        let trailing: String   // spaces/punctuation after the word, kept with it so lines never wrap before a comma
    }

    private var chunks: [Chunk] {
        var result: [Chunk] = []
        var i = 0
        while i < segments.count {
            let s = segments[i]
            if s.token != nil {
                var trailing = ""
                if i + 1 < segments.count, segments[i + 1].token == nil { trailing = segments[i + 1].text; i += 1 }
                result.append(Chunk(id: result.count, token: s.token, text: s.text, trailing: trailing))
            } else {
                result.append(Chunk(id: result.count, token: nil, text: s.text, trailing: ""))
            }
            i += 1
        }
        return result
    }

    private func isContent(_ chunk: Chunk) -> Bool {
        guard let token = chunk.token else { return false }
        return profile?.contentPOS.contains(token.pos) == true
    }

    /// The words that have a meaning to show; the ones the keyboard can land on.
    private var contentChunks: [Chunk] { chunks.filter(isContent) }

    private var isFocused: Bool { focusedLine.wrappedValue == index }

    private var reservesRuby: Bool {
        (profile?.display.showsReadings ?? false) && segments.contains { $0.token?.reading != nil }
    }

    /// The transcript's text.
    private var textFont: Font { .system(size: size.points, weight: .regular, design: .rounded) }

    /// Furigana is a reading aid set above the text, conventionally about half its size, so it is exempt from the
    /// 12 pt minimum used elsewhere. The full-size reading is always in the hint bar.
    private var rubySize: CGFloat { max(10, (size.points * 0.55).rounded()) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(stamp(line.startTime))
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(active ? Theme.ink : Theme.muted)
            if segments.isEmpty {
                Text(line.text).font(textFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout {
                    ForEach(chunks) { chunk in chunkView(chunk) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Line at \(stamp(line.startTime))")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No outline at rest: the line being played is filled, and a line you point at or tab to gets a border.
        .background(RoundedRectangle(cornerRadius: 14).fill(active ? Theme.softStrong : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder((rowHovered || isFocused) ? Theme.ink.opacity(0.45) : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { focusedLine.wrappedValue = index; seek() }
        .onHover { rowHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: rowHovered)
        .contextMenu {
            Button("Edit line…", action: edit)
            Divider()
            Button("Save audio clip…", action: exportAudio)
            Button("Save video clip…", action: exportVideo)
        }
        .accessibilityAction(named: "Jump to this line", seek)
        .accessibilityAction(named: "Edit line", edit)
        .focusable()
        .focused(focusedLine, equals: index)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { moveCaret(-1) }
        .onKeyPress(.rightArrow) { moveCaret(1) }
        .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        .onKeyPress(.return) { pinCaret() }
        .onKeyPress(.escape) {
            guard pinned != nil else { return .ignored }
            pinned = nil
            return .handled
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                caret = min(caret, max(0, contentChunks.count - 1))
                hovered = contentChunks[safe: caret]?.token
            } else if let token = contentChunks[safe: caret]?.token, hovered == token {
                hovered = nil
            }
        }
        .task(id: line.text) {
            guard let profile else { return }
            let text = line.text
            segments = await Task.detached { profile.lineSegments(in: text) }.value
        }
    }

    // MARK: Keyboard

    private func moveCaret(_ step: Int) -> KeyPress.Result {
        guard !contentChunks.isEmpty else { return .ignored }
        caret = min(contentChunks.count - 1, max(0, caret + step))
        hovered = contentChunks[caret].token
        return .handled
    }

    private func pinCaret() -> KeyPress.Result {
        guard let token = contentChunks[safe: caret]?.token else { return .ignored }
        togglePin(token)
        return .handled
    }

    private func togglePin(_ token: Token) {
        pinned = pinned == token ? nil : token
    }

    // MARK: Words

    private func chunkView(_ chunk: Chunk) -> some View {
        let content = isContent(chunk)
        let isHovered = hoveredChunk == chunk.id
        let hasCaret = isFocused && content && contentChunks[safe: caret]?.id == chunk.id
        let isPinned = content && chunk.token != nil && pinned == chunk.token
        let showRuby = rowHovered || isFocused
        let view = VStack(spacing: 0) {
            if reservesRuby {
                // Always reserved, so showing furigana never moves the text.
                Text(chunk.token?.reading ?? " ")
                    .font(.system(size: rubySize, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .opacity(showRuby && chunk.token?.reading != nil ? 1 : 0)
                    .accessibilityHidden(true)   // VoiceOver gets the reading in the word's label
            }
            HStack(spacing: 0) {
                Text(chunk.text)
                    .font(textFont)
                    .learningUnderline(status(of: chunk.token) == .learning)
                    // The highlight is slightly wider than the word, but takes no layout space (no gaps in Japanese).
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(isPinned ? Theme.ink.opacity(0.2) : isHovered ? Theme.ink.opacity(0.12) : tint(for: chunk.token))
                        .padding(.horizontal, -1))
                    .overlay {
                        // The keyboard's place, drawn as an outline so it doesn't rest on colour.
                        if hasCaret { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.ink, lineWidth: 2).padding(-2) }
                    }
                if !chunk.trailing.isEmpty {
                    Text(chunk.trailing).font(textFont)
                }
            }
        }
        // The word's own baseline is what a label beside the line lines up with, not the furigana above it.
        .alignmentGuide(.firstTextBaseline) { d in d[.lastTextBaseline] }
        .onHover { inside in
            guard let token = chunk.token, content else { return }
            if inside {
                hoveredChunk = chunk.id
                hovered = token
            } else if hoveredChunk == chunk.id {
                hoveredChunk = nil
                if hovered == token { hovered = nil }
            }
        }
        return accessible(view, chunk)
    }

    /// A word with a meaning is a button for VoiceOver: its label carries the reading and its status (which
    /// sighted users get from colour), and activating it pins the meaning, which is then announced.
    @ViewBuilder
    private func accessible<V: View>(_ view: V, _ chunk: Chunk) -> some View {
        if isContent(chunk), let token = chunk.token {
            view
                .onTapGesture {
                    focusedLine.wrappedValue = index
                    togglePin(token)
                    seek()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chunk.text + (token.reading.map { ", read \($0)" } ?? ""))
                .accessibilityValue(status(of: token).map { $0 == .new ? "" : $0.title } ?? "")
                .accessibilityHint("Shows what it means")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { togglePin(token) }
        } else {
            view
        }
    }

    private func status(of token: Token?) -> WordStatus? {
        token.flatMap { statuses[WordKey(lemma: $0.lemma, pos: $0.pos)] }
    }

    /// Colour is never the only signal: a learning word is marked by a thin underline alone, which stays quiet in a
    /// full line; a known (and finished) word has a soft green tint; untouched words get nothing.
    /// (The underline is `learningUnderline`; this is only the background.)
    private func tint(for token: Token?) -> Color {
        guard let current = status(of: token) else { return .clear }
        switch current {
        case .learning: return .clear
        case .known, .finished: return Theme.green.opacity(0.22)
        case .new: return .clear
        }
    }

    private func stamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension View {
    /// A thin, soft underline for a word you are learning. Thinner and calmer than the system underline, and it
    /// takes no layout space.
    func learningUnderline(_ on: Bool = true) -> some View {
        overlay(alignment: .bottom) {
            if on { Capsule().fill(Theme.orange.opacity(0.8)).frame(height: 1.5).padding(.horizontal, 1).offset(y: 1) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// How large the transcript's text is. The Mac has no system text-size setting, so the app keeps its own.
enum TranscriptSize: String, CaseIterable {
    case small, standard, large, larger

    static let key = "transcriptSize"
    var points: CGFloat {
        switch self {
        case .small: 15
        case .standard: 18
        case .large: 22
        case .larger: 26
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        }
    }
}
