import LangCore
import SwiftUI

/// One subtitle line. Words are hoverable; hovering the line shows furigana above Japanese words.
struct SubtitleRow: View {
    let line: Subtitle
    let active: Bool
    let profile: (any LanguageProfile)?
    /// Empty when highlighting is off.
    let statuses: [WordKey: WordStatus]
    @Binding var hovered: Token?
    let seek: () -> Void
    let exportAudio: () -> Void
    let exportVideo: () -> Void

    @State private var segments: [LineSegment] = []
    @State private var rowHovered = false
    @State private var hoveredChunk: Int?

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

    private var reservesRuby: Bool {
        (profile?.display.showsReadings ?? false) && segments.contains { $0.token?.reading != nil }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(stamp(line.startTime))
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(active ? Theme.ink : .secondary)
            if segments.isEmpty {
                Text(line.text).font(.system(.body, design: .rounded, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout {
                    ForEach(chunks) { chunk in chunkView(chunk) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(active ? Theme.soft : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? Theme.ink.opacity(0.6) : Theme.line.opacity(0.7), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: seek)
        .onHover { rowHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: rowHovered)
        .contextMenu {
            Button("Save audio clip…", action: exportAudio)
            Button("Save video clip…", action: exportVideo)
        }
        .task {
            guard let profile else { return }
            let text = line.text
            segments = await Task.detached { profile.lineSegments(in: text) }.value
        }
    }

    private func chunkView(_ chunk: Chunk) -> some View {
        let isHovered = hoveredChunk == chunk.id
        return VStack(spacing: 0) {
            if reservesRuby {
                // Always reserved, so showing furigana on hover never moves the text.
                Text(chunk.token?.reading ?? " ")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .opacity(rowHovered && chunk.token?.reading != nil ? 1 : 0)
            }
            HStack(spacing: 0) {
                Text(chunk.text)
                    .underline(status(of: chunk.token) == .learning, pattern: .dot, color: Theme.orange)
                    .font(.system(.body, design: .rounded, weight: .regular))
                    // The highlight is slightly wider than the word, but takes no layout space (no gaps in Japanese).
                    .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Theme.ink.opacity(0.12) : tint(for: chunk.token)).padding(.horizontal, -1))
                if !chunk.trailing.isEmpty {
                    Text(chunk.trailing).font(.system(.body, design: .rounded, weight: .regular))
                }
            }
        }
        .onHover { inside in
            guard let token = chunk.token, profile?.contentPOS.contains(token.pos) == true else { return }
            if inside {
                hoveredChunk = chunk.id
                hovered = token
            } else if hoveredChunk == chunk.id {
                hoveredChunk = nil
                if hovered == token { hovered = nil }
            }
        }
    }

    private func status(of token: Token?) -> WordStatus? {
        token.flatMap { statuses[WordKey(lemma: $0.lemma, pos: $0.pos)] }
    }

    /// Colour is never the only signal: learning words also get a dotted underline. Learning is orange, known (and
    /// burned) green; untouched words get nothing, so they stay quiet.
    private func tint(for token: Token?) -> Color {
        guard let current = status(of: token) else { return .clear }
        switch current {
        case .learning: return Theme.orange.opacity(0.30)
        case .known, .burned: return Theme.green.opacity(0.22)
        case .new: return .clear
        }
    }

    private func stamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
