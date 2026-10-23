import AVKit
import LangCore
import SwiftUI

struct PlayerView: View {
    let env: LangEnvironment
    let video: Video
    let startAt: Double?
    let backTitle: String
    let close: () -> Void

    @State private var controller: PlaybackController?
    @State private var message: String?
    @State private var failure: String?
    @State private var hoveredToken: Token?
    @State private var hint: WordHint?
    /// Status of every word in this video, so learning and known words can be tinted in the subtitles.
    @State private var statuses: [WordKey: WordStatus] = [:]
    @AppStorage("highlightWords") private var highlightWords = true
    @Environment(AppState.self) private var app

    private var profile: (any LanguageProfile)? { LanguageProfiles.profile(for: video.language) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if let controller {
                    content(controller)
                } else if let failure {
                    ContentUnavailableView("Can't play this video", systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(video.title)
        .task { await load() }
        .task(id: hoveredToken?.lemma) { await refreshHint() }
        .task(id: app.dataVersion) {
            guard let id = video.id else { return }
            statuses = (try? await env.database.wordStatuses(videoID: id)) ?? [:]
        }
        .onDisappear { controller?.stop() }
    }

    private func refreshHint() async {
        guard let token = hoveredToken else { hint = nil; return }
        hint = await env.hint(for: token, language: video.language)
    }

    /// Start learning or mark known without leaving the video.
    private func setStatus(_ status: WordStatus) {
        guard let id = hint?.wordID else { return }
        Task {
            switch status {
            case .learning: try? await env.database.startLearning(wordID: id)
            default: try? await env.database.markKnown(wordID: id)
            }
            app.dataChanged()
            await refreshHint()
        }
    }

    /// A visible way back, inside the card.
    private var topBar: some View {
        HStack(spacing: 14) {
            Button("Back", systemImage: "chevron.left") { close() }
                .buttonStyle(.chunky(.secondary, compact: true))
                .help("Back to \(backTitle)")
            Text("Back to \(backTitle)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            Text(video.title).font(.system(.callout, design: .rounded, weight: .semibold)).lineLimit(1).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    private func load() async {
        do {
            let new = try await env.playback(for: video)
            controller = new
            if let startAt { await new.seek(to: startAt, play: true) }
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: Layout

    private func content(_ controller: PlaybackController) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                VideoPlayer(player: controller.player)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 2))
                controls(controller)
            }
            .padding(20)
            .frame(minWidth: 380)

            Rectangle().fill(Theme.line).frame(width: 2)

            VStack(spacing: 0) {
                legendBar
                subtitleList(controller)
                hintBar
                if let message {
                    Text(message).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(8).frame(maxWidth: .infinity).background(Theme.pinkSoft)
                }
            }
            .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)
        }
    }

    private func controls(_ controller: PlaybackController) -> some View {
        HStack(spacing: 12) {
            Button("Previous line", systemImage: "backward.fill") { Task { await controller.previousLine() } }
                .buttonStyle(.chunky(.secondary, compact: true))
            Button(controller.isPlaying ? "Pause" : "Play", systemImage: controller.isPlaying ? "pause.fill" : "play.fill") {
                controller.togglePlayback()
            }
            .buttonStyle(.chunky(compact: true))
            .keyboardShortcut(.space, modifiers: [])
            Button("Next line", systemImage: "forward.fill") { Task { await controller.nextLine() } }
                .buttonStyle(.chunky(.secondary, compact: true))
            Menu {
                Picker("Speed", selection: Binding(get: { controller.speed }, set: { controller.speed = $0 })) {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { Text(speedLabel($0)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(speedLabel(controller.speed)).frame(minWidth: 30)
            }
            .menuStyle(.button).buttonStyle(.chunky(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
            .help("Playback speed")
        }
        .labelStyle(.iconOnly)
    }

    /// What the tints mean, and one switch for them. Two states only: a burned word is simply a known one.
    private var legendBar: some View {
        HStack(spacing: 14) {
            legendDot(Theme.orange, "Learning", underlined: true)
            legendDot(Theme.green, "Known")
            Spacer()
            Toggle("Highlight", isOn: $highlightWords)
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 2) }
    }

    private func legendDot(_ color: Color, _ label: String, underlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color.opacity(0.85)).frame(width: 8, height: 8)
            // The same marks the subtitles use, so the legend is a true sample, not a description.
            Text(label).underline(underlined, pattern: .dot, color: color)
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private func subtitleList(_ controller: PlaybackController) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(controller.lines.enumerated()), id: \.offset) { index, line in
                        SubtitleRow(
                            line: line, active: controller.activeIndex == index, profile: profile,
                            statuses: highlightWords ? statuses : [:],
                            hovered: $hoveredToken,
                            seek: { Task { await controller.seek(toLine: index) } },
                            exportAudio: { export(line, kind: .audio) },
                            exportVideo: { export(line, kind: .video) })
                        .id(index)
                    }
                }
                .padding(14)
            }
            .onChange(of: controller.activeIndex) { _, new in
                if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
    }

    /// Fixed-height strip under the subtitles: the meaning of the word under the pointer.
    private var hintBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let token = hoveredToken {
                HStack(spacing: 8) {
                    Text(hint?.lemma ?? token.lemma).font(Theme.title(17))
                    if let reading = hint?.reading ?? token.reading {
                        Text(reading).font(.system(.callout, design: .rounded, weight: .bold)).foregroundStyle(Theme.pinkText)
                    }
                    StatusPill(text: token.pos.rawValue, color: .secondary)
                    if let status = hint?.status {
                        StatusPill(text: status.rawValue, color: color(for: status))
                    }
                    Spacer()
                    if hint?.wordID != nil {
                        if hint?.status != .learning && hint?.status != .burned {
                            Button("Learn") { setStatus(.learning) }.buttonStyle(.chunky(compact: true))
                                .help("Start learning this word")
                        }
                        if hint?.status != .known {
                            Button("Known") { setStatus(.known) }.buttonStyle(.chunky(.secondary, compact: true))
                                .help("Mark this word as known")
                        }
                    }
                }
                Text(hint?.gloss ?? "No dictionary entry").font(.system(.callout, design: .rounded)).lineLimit(2)
                    .foregroundStyle(hint?.gloss == nil ? .secondary : .primary)
            } else {
                Text("Hover a word in the subtitles to see what it means.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.pinkSoft.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 2) }
    }

    private func speedLabel(_ speed: Float) -> String {
        (speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", speed)) + "×"
    }

    private func color(for status: WordStatus) -> Color {
        switch status {
        case .new: .secondary
        case .learning: Theme.orange
        case .known: Theme.green
        case .burned: Theme.purple
        }
    }

    // MARK: Export

    private func export(_ line: Subtitle, kind: ClipKind) {
        let name = "\(ClipExporter.sanitized(video.title)) \(stamp(line.startTime).replacingOccurrences(of: ":", with: "-"))"
        guard let url = ExportPanels.saveFile(suggestedName: name, fileExtension: kind.fileExtension) else { return }
        message = "Exporting…"
        Task {
            do {
                try await env.clips.export(video: video, start: line.startTime, end: line.endTime, kind: kind, to: url)
                message = "Saved \(url.lastPathComponent)"
            } catch {
                message = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func stamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One subtitle line. Words are hoverable; hovering the line shows furigana above Japanese words.
private struct SubtitleRow: View {
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

    private struct Chunk: Identifiable {
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
                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(active ? Theme.pinkText : .secondary)
            if segments.isEmpty {
                Text(line.text).font(.system(.body, design: .rounded, weight: active ? .semibold : .regular))
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
        .background(RoundedRectangle(cornerRadius: 14).fill(active ? Theme.pinkSoft : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? Theme.pink : Theme.line.opacity(0.7), lineWidth: 2))
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
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.pinkText)
                    .opacity(rowHovered && chunk.token?.reading != nil ? 1 : 0)
            }
            HStack(spacing: 0) {
                Text(chunk.text)
                    .underline(status(of: chunk.token) == .learning, pattern: .dot, color: Theme.orange)
                    .font(.system(.body, design: .rounded, weight: active ? .semibold : .regular))
                    // The highlight is slightly wider than the word, but takes no layout space (no gaps in Japanese).
                    .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Theme.pink.opacity(0.22) : tint(for: chunk.token)).padding(.horizontal, -1))
                if !chunk.trailing.isEmpty {
                    Text(chunk.trailing).font(.system(.body, design: .rounded, weight: active ? .semibold : .regular))
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
