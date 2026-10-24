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
    /// A word whose meaning is kept in the hint bar until you unpin it, so its buttons can be reached.
    @State private var pinnedToken: Token?
    @State private var hint: WordHint?
    @FocusState private var focusedLine: Int?
    /// The last word the pointer was on, kept for a moment (and while the pointer is on the hint bar) so the buttons
    /// in the bar can be reached.
    @State private var lingerToken: Token?
    @State private var barHovered = false
    @State private var lingerTask: Task<Void, Never>?
    /// Status of every word in this video, so learning and known words can be tinted in the subtitles.
    @State private var statuses: [WordKey: WordStatus] = [:]
    @AppStorage("highlightWords") private var highlightWords = true
    @Environment(AppState.self) private var app

    private var profile: (any LanguageProfile)? { LanguageProfiles.profile(for: video.language) }
    /// The word the hint bar describes: the pinned one, else the one under the pointer or the keyboard.
    private var shownToken: Token? { pinnedToken ?? hoveredToken ?? lingerToken }

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
        .task(id: shownToken?.lemma) { await refreshHint(announce: pinnedToken != nil) }
        .task(id: app.dataVersion) {
            guard let id = video.id else { return }
            statuses = (try? await env.database.wordStatuses(videoID: id)) ?? [:]
        }
        .onChange(of: hoveredToken) { _, new in
            lingerTask?.cancel()
            if let new { lingerToken = new; return }
            lingerTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled, !barHovered else { return }
                lingerToken = nil
            }
        }
        .onDisappear { controller?.stop() }
    }

    private func refreshHint(announce: Bool = false) async {
        guard let token = shownToken else { hint = nil; return }
        hint = await env.hint(for: token, language: video.language)
        // VoiceOver can't hover, so pinning a word reads its meaning aloud.
        if announce, let hint {
            AccessibilityNotification.Announcement("\(hint.lemma). \(hint.gloss ?? "No dictionary entry")").post()
        }
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
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
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
                            line: line, index: index, active: controller.activeIndex == index, profile: profile,
                            statuses: highlightWords ? statuses : [:],
                            hovered: $hoveredToken, pinned: $pinnedToken, focusedLine: $focusedLine,
                            moveFocus: { delta in
                                let target = index + delta
                                guard controller.lines.indices.contains(target) else { return }
                                withAnimation { proxy.scrollTo(target, anchor: .center) }
                                Task { @MainActor in focusedLine = target }   // after the row exists, if it was off screen
                            },
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

    /// Fixed-height strip under the subtitles: the meaning of the word that is pinned, or under the pointer or keyboard.
    private var hintBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let token = shownToken {
                HStack(spacing: 8) {
                    Text(hint?.lemma ?? token.lemma).font(Theme.title(17))
                    if let reading = hint?.reading ?? token.reading {
                        Text(reading).font(.system(.callout, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    StatusPill(text: token.pos.rawValue)
                    SpeakButton(text: hint?.reading ?? token.reading ?? hint?.lemma ?? token.lemma,
                                languageCode: profile?.whisperCode ?? video.language, shortcut: "s")
                    if let status = hint?.status {
                        StatusBadge(status: status, stage: hint?.stage)
                    }
                    Spacer()
                    if hint?.wordID != nil {
                        if hint?.status != .learning && hint?.status != .burned {
                            Button("Learn") { setStatus(.learning) }.buttonStyle(.pill(compact: true))
                                .keyboardShortcut("l", modifiers: [])
                                .help("Start learning this word (L)")
                        }
                        if hint?.status != .known {
                            Button("Known") { setStatus(.known) }.buttonStyle(.pill(.secondary, compact: true))
                                .keyboardShortcut("k", modifiers: [])
                                .help("Mark this word as known (K)")
                        }
                    }
                    if pinnedToken != nil {
                        Button("Unpin", systemImage: "pin.slash") { pinnedToken = nil }
                            .labelStyle(.iconOnly).buttonStyle(.pill(.secondary, compact: true))
                            .help("Stop keeping this word here (Esc)")
                    }
                }
                Text(hint?.gloss ?? "No dictionary entry").font(.system(.callout, design: .rounded)).lineLimit(2)
                    .foregroundStyle(hint?.gloss == nil ? Theme.muted : Theme.ink)
            } else {
                Text("Hover a word to see what it means. Click it to keep it here, or use the arrow keys and Return.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.soft.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .onHover { inside in
            barHovered = inside
            guard !inside, hoveredToken == nil else { return }
            lingerTask?.cancel()
            lingerTask = Task {
                try? await Task.sleep(for: .seconds(0.4))
                guard !Task.isCancelled, !barHovered else { return }
                lingerToken = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word meaning")
    }

    private func speedLabel(_ speed: Float) -> String {
        (speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", speed)) + "×"
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
