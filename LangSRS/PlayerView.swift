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
                .buttonStyle(.pill(.secondary, compact: true))
                .help("Back to \(backTitle)")
            Text("Back to \(backTitle)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.muted)
            Spacer()
            Text(video.title).font(.system(.callout, design: .rounded, weight: .semibold)).lineLimit(1).foregroundStyle(Theme.muted)
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
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
                controls(controller)
            }
            .padding(20)
            .frame(minWidth: 380)

            Rectangle().fill(Theme.line).frame(width: 1)

            VStack(spacing: 0) {
                legendBar
                subtitleList(controller)
                hintBar
                if let message {
                    Text(message).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(8).frame(maxWidth: .infinity).background(Theme.soft)
                }
            }
            .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)
        }
    }

    private func controls(_ controller: PlaybackController) -> some View {
        HStack(spacing: 12) {
            Button("Previous line", systemImage: "backward.fill") { Task { await controller.previousLine() } }
                .buttonStyle(.pill(.secondary, compact: true))
            Button(controller.isPlaying ? "Pause" : "Play", systemImage: controller.isPlaying ? "pause.fill" : "play.fill") {
                controller.togglePlayback()
            }
            .buttonStyle(.pill(compact: true))
            .keyboardShortcut(.space, modifiers: [])
            Button("Next line", systemImage: "forward.fill") { Task { await controller.nextLine() } }
                .buttonStyle(.pill(.secondary, compact: true))
            Menu {
                Picker("Speed", selection: Binding(get: { controller.speed }, set: { controller.speed = $0 })) {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { Text(speedLabel($0)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(speedLabel(controller.speed)).frame(minWidth: 30)
            }
            .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
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
                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func legendDot(_ color: Color, _ label: String, underlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color.opacity(0.85)).frame(width: 8, height: 8)
            // The same marks the subtitles use, so the legend is a true sample, not a description.
            Text(label).underline(underlined, pattern: .dot, color: color)
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
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
                        Text(reading).font(.system(.callout, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    StatusPill(text: token.pos.rawValue)
                    if let status = hint?.status {
                        StatusPill(text: status.rawValue, color: color(for: status))
                    }
                    Spacer()
                    if hint?.wordID != nil {
                        if hint?.status != .learning && hint?.status != .burned {
                            Button("Learn") { setStatus(.learning) }.buttonStyle(.pill(compact: true))
                                .help("Start learning this word")
                        }
                        if hint?.status != .known {
                            Button("Known") { setStatus(.known) }.buttonStyle(.pill(.secondary, compact: true))
                                .help("Mark this word as known")
                        }
                    }
                }
                Text(hint?.gloss ?? "No dictionary entry").font(.system(.callout, design: .rounded)).lineLimit(2)
                    .foregroundStyle(hint?.gloss == nil ? .secondary : .primary)
            } else {
                Text("Hover a word in the subtitles to see what it means.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.soft.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
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
