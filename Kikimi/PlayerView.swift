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
    /// Where you stopped last time, while the choice to continue from there or start over is on offer.
    @State private var resumeOffer: Double?
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
    /// Where the transcript and meaning bar are in the window, and the mouse watcher that uses it: a click anywhere
    /// outside them lets go of a pinned word.
    @State private var panelFrame: CGRect = .zero
    @State private var clickMonitor: Any?
    /// Status of every word in this video, so learning and known words can be tinted in the subtitles.
    @State private var statuses: [WordKey: WordStatus] = [:]
    @AppStorage("highlightWords") private var highlightWords = true
    @AppStorage("pauseAfterLine") private var pauseAfterLine = false
    /// How fast a looped line plays (1 is normal).
    @AppStorage("loopSpeed") private var loopSpeed = 1.0
    @AppStorage(TranslationPreferences.displayKey) private var translationDisplayRaw = TranslationDisplay.onRequest.rawValue
    /// This video's translations (nil when they are off, or the video is already in the chosen language).
    @State private var translations: LineTranslations?
    /// The lines whose translation is on screen, in "when I ask" mode.
    @State private var shownTranslations: Set<Int64> = []
    /// The line being corrected, with its place in the transcript.
    @State private var editing: (index: Int, line: Subtitle)?
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profile: (any LanguageProfile)? { LanguageProfiles.profile(for: video.language) }
    private var translationMode: TranslationDisplay { TranslationDisplay(rawValue: translationDisplayRaw) ?? .onRequest }
    /// The word the hint bar describes: the pinned one, else the one under the pointer or the keyboard.
    private var shownToken: Token? { pinnedToken ?? hoveredToken ?? lingerToken }

    var body: some View {
        Group {
            if let controller {
                content(controller)   // the Back button is in its left column, so the side panel runs to the top
            } else {
                VStack(spacing: 0) {
                    topBar.padding(.horizontal, 20).padding(.top, 20)
                    Group {
                        if let failure {
                            ContentUnavailableView("Can't play this video", systemImage: "exclamationmark.triangle",
                                                   description: Text(failure))
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .task(id: shownToken?.lemma) { await refreshHint(announce: pinnedToken != nil) }
        .task(id: controller != nil) { await keepPlace() }
        .onChange(of: pauseAfterLine) { _, on in controller?.pausesAfterLines = on }
        .onChange(of: translationDisplayRaw) { _, _ in Task { await setUpTranslations() } }
        .onChange(of: translations?.problem) { _, text in if let text { message = text } }
        .onChange(of: loopSpeed) { _, speed in controller?.loopSpeed = Float(speed) }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing, let controller {
                EditLineSheet(
                    line: editing.line, duration: video.duration, profile: profile, env: env,
                    preview: { start, end in Task { await controller.playRange(from: start, to: end) } },
                    saved: { saved in
                        controller.replaceLine(at: editing.index, with: saved)
                        if let id = saved.id {   // what was translated was the old text
                            translations?.forget(id)
                            if translationMode == .always || shownTranslations.contains(id) { translations?.need(saved) }
                        }
                        app.dataChanged()
                        self.editing = nil
                    }, cancel: { controller.pause(); self.editing = nil })
            }
        }
        .onChange(of: message) { _, text in
            if let text { AccessibilityNotification.Announcement(text).post() }   // VoiceOver can't see the status line change
        }
        .onChange(of: controller?.isPlaying) { _, playing in if playing == true { resumeOffer = nil } }
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
        .onAppear { installClickMonitor() }
        .onDisappear {
            savePlace()
            controller?.stop()
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if pinnedToken != nil, panelFrame != .zero, !panelFrame.contains(event.locationInWindow) {
                pinnedToken = nil
            }
            return event   // the click carries on to whatever was clicked
        }
    }

    private func refreshHint(announce: Bool = false) async {
        guard let token = shownToken else { hint = nil; return }
        hint = await env.hint(for: token, language: video.language)
        // VoiceOver can't hover, so pinning a word reads its meaning aloud.
        if announce, let hint {
            AccessibilityNotification.Announcement("\(hint.lemma). \(hint.gloss ?? "No dictionary entry")").post()
        }
        // Pinning a word is looking it up on purpose (hovering is not), so it goes in the tally.
        if announce, let wordID = hint?.wordID { try? await env.database.record(.lookup, subject: wordID) }
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
            Button(backTitle, systemImage: "chevron.left") { close() }
                .buttonStyle(.pill(.secondary, compact: true))
                .help("Back to \(backTitle)")
            Spacer()
        }
    }

    private func load() async {
        do {
            let new = try await env.playback(for: video)
            new.pausesAfterLines = pauseAfterLine
            new.loopSpeed = Float(loopSpeed)
            if let videoID = video.id {
                let database = env.database
                new.onListened = { seconds in Task { try? await database.record(.listen, subject: videoID, amount: seconds) } }
            }
            controller = new
            await setUpTranslations()
            if let startAt {
                await new.seek(to: startAt, play: true)
            } else if let id = video.id, let spot = try? await env.database.video(id: id)?.resumePosition {
                await new.seek(to: spot)   // waits, paused, until you choose
                resumeOffer = spot
                AccessibilityNotification.Announcement(String(localized: "You stopped at \(clock(spot)). Continue or start over.")).post()
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Starts translating this video's lines when translations are on and a translation is wanted.
    private func setUpTranslations() async {
        guard translations == nil, translationMode != .off, let id = video.id, let profile,
              let service = env.translationService(for: profile) else { return }
        let model = LineTranslations(service: service, videoID: id, source: profile.whisperCode, target: service.target)
        translations = model
        await model.load()
    }

    private func toggleTranslation(of line: Subtitle) {
        guard let id = line.id else { return }
        if shownTranslations.contains(id) { shownTranslations.remove(id) }
        else { shownTranslations.insert(id); translations?.need(line) }
    }

    // MARK: Layout

    private func content(_ controller: PlaybackController) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                topBar
                VideoPlayer(player: controller.player)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
                if let resumeOffer { resumeBar(resumeOffer, controller) }
                controls(controller)
            }
            .padding(20)
            .frame(minWidth: 380)

            Rectangle().fill(Theme.line).frame(width: 1)

            VStack(spacing: 0) {
                titleBar
                legendBar
                subtitleList(controller)
                hintBar
                if let message {
                    Text(message).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(8).frame(maxWidth: .infinity).background(Theme.soft)
                }
            }
            .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)
            .background(WindowFrameReader { panelFrame = $0 })
        }
    }

    /// Offered when you come back to a video you stopped part-way through.
    private func resumeBar(_ spot: Double, _ controller: PlaybackController) -> some View {
        HStack(spacing: 10) {
            Text("You stopped at \(clock(spot)).").font(Theme.small).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Button("Start over") {
                resumeOffer = nil
                Task { await controller.seek(to: 0, play: true) }
            }
            .buttonStyle(.pill(.secondary, compact: true))
            Button("Continue") {
                resumeOffer = nil
                controller.play()
            }
            .buttonStyle(.pill(compact: true))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You stopped at \(clock(spot))")
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Remembers the place every few seconds while the video plays, so a crash or quit loses little.
    private func keepPlace() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if controller?.isPlaying == true { savePlace() }
        }
    }

    private func savePlace() {
        guard let controller, let id = video.id else { return }
        let seconds = controller.currentTime, database = env.database
        Task { try? await database.saveResumePosition(videoID: id, seconds: seconds) }
    }

    private func controls(_ controller: PlaybackController) -> some View {
        HStack(spacing: 12) {
            Button("Previous line", systemImage: "backward.fill") { Task { await controller.previousLine() } }
                .buttonStyle(.pill(.secondary, compact: true))
            Button(controller.isPlaying ? String(localized: "Pause") : String(localized: "Play"), systemImage: controller.isPlaying ? "pause.fill" : "play.fill") {
                controller.togglePlayback()
            }
            .buttonStyle(.pill(compact: true))
            .keyboardShortcut(.space, modifiers: [])
            Button("Next line", systemImage: "forward.fill") { Task { await controller.nextLine() } }
                .buttonStyle(.pill(.secondary, compact: true))
            Button("Pause after each line", systemImage: "pause.rectangle") { pauseAfterLine.toggle() }
                .buttonStyle(.pill(pauseAfterLine ? .primary : .secondary, compact: true))
                .keyboardShortcut("p", modifiers: [])
                .help(pauseAfterLine ? "Pausing after each line (P). Press again to play straight through."
                                     : "Pause after each line (P), to think or look a word up")
                .accessibilityValue(pauseAfterLine ? "On" : "Off")
            Button("Loop this line", systemImage: "repeat") { Task { await controller.toggleLoop() } }
                .buttonStyle(.pill(controller.loopingIndex != nil ? .primary : .secondary, compact: true))
                .keyboardShortcut("r", modifiers: [])
                .help(controller.loopingIndex != nil ? "Looping this line (R). Press again to stop."
                                                     : "Repeat this line (R), until you stop it")
                .accessibilityValue(controller.loopingIndex != nil ? "On" : "Off")
            // Only while a line is looping: it has no meaning otherwise.
            if controller.loopingIndex != nil {
                Menu {
                    Picker("Loop speed", selection: $loopSpeed) {
                        ForEach([1.0, 0.75, 0.5], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(String(format: "%g×", loopSpeed)).frame(minWidth: 30)
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                .help("How fast the looped line plays")
                .accessibilityLabel("Loop speed")
                .transition(.opacity)
            }
        }
        .labelStyle(.pillIcon)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: controller.loopingIndex != nil)
    }

    /// The video's title, at the top of the transcript panel, left-aligned.
    private var titleBar: some View {
        Text(video.title)
            .font(Theme.title(17))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    /// What the tints mean, and one switch for them. Two states only: a finished word is simply a known one.
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
            if !underlined { Circle().fill(color.opacity(0.85)).frame(width: 8, height: 8) }
            // The same marks the subtitles use, so the legend is a true sample, not a description.
            Text(label).learningUnderline(underlined)
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }

    private func subtitleList(_ controller: PlaybackController) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(controller.lines.enumerated()), id: \.offset) { index, line in
                        SubtitleRow(
                            line: line, index: index, active: controller.activeIndex == index, profile: profile,
                            statuses: highlightWords ? statuses : [:],
                            hovered: $hoveredToken, pinned: $pinnedToken, focusedLine: $focusedLine,
                            moveFocus: { delta in
                                let target = index + delta
                                guard controller.lines.indices.contains(target) else { return }
                                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(target, anchor: .center) }
                                Task { @MainActor in focusedLine = target }   // after the row exists, if it was off screen
                            },
                            seek: { Task { await controller.seek(toLine: index) } },
                            exportAudio: { export(line, kind: .audio) },
                            exportVideo: { export(line, kind: .video) },
                            edit: { editing = (index, line) },
                            translationMode: translations == nil ? .off : translationMode,
                            translation: line.id.flatMap { translations?.texts[$0] },
                            translationShown: translationMode == .always || (line.id.map(shownTranslations.contains) ?? false),
                            translationWaiting: line.id.map { translations?.waiting.contains($0) ?? false } ?? false,
                            toggleTranslation: { toggleTranslation(of: line) },
                            wantTranslation: { translations?.need(line) })
                        .id(index)
                    }
                }
                .padding(10)
            }
            .onChange(of: controller.activeIndex) { _, new in
                if let new { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(new, anchor: .center) } }
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
                    StatusPill(text: token.pos.title)
                    // Japanese verbs and adjectives show the form they are in; the link opens the page on how it is built.
                    if let stem = TsumikiStem.stem(for: token) {
                        Link(destination: stem.url) {
                            Text("\(stem.name) ↗").font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.ink)
                        .help("How \(stem.label) is built (opens Tsumiki, a Japanese grammar guide, in your browser)")
                        .accessibilityLabel("Grammar: \(stem.name), \(stem.label). Opens a web page.")
                    }
                    // A new word needs no badge: Learn and Known beside it already say it is new.
                    if let status = hint?.status, status != .new {
                        StatusBadge(status: status, stage: hint?.stage)
                    }
                    Spacer()
                    if hint?.wordID != nil {
                        if hint?.status != .learning && hint?.status != .finished {
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
                }
                Text(hint?.gloss ?? "No dictionary entry").font(.system(.callout, design: .rounded)).lineLimit(2)
                    .foregroundStyle(hint?.gloss == nil ? Theme.muted : Theme.ink)
            } else {
                Text("Hover a word to see what it means. Click it to keep it here, and click anywhere else to let go.")
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

    // MARK: Export

    private func export(_ line: Subtitle, kind: ClipKind) {
        let name = "\(ClipExporter.sanitized(video.title)) \(stamp(line.startTime).replacingOccurrences(of: ":", with: "-"))"
        guard let url = ExportPanels.saveFile(suggestedName: name, fileExtension: kind.fileExtension) else { return }
        message = String(localized: "Exporting…")
        Task {
            do {
                try await env.clips.export(video: video, start: line.startTime, end: line.endTime, kind: kind, to: url)
                message = String(localized: "Saved \(url.lastPathComponent)")
            } catch {
                message = String(localized: "Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func stamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
