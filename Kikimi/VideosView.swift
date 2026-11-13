import AppKit
import LangCore
import SwiftUI

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct VideosView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    @State private var items: [LibraryEntry] = []
    @State private var totalBytes: Int64 = 0
    @State private var coverages: [Int64: VideoCoverage] = [:]
    /// "newest" or "fit": how the list is ordered. Best fit puts the videos you can most comfortably follow first.
    @AppStorage("videoSort") private var sort = "newest"
    @State private var playing: Video?
    @State private var startAt: Double?
    @State private var info: Video?
    @State private var calibrating: Video?
    @State private var renaming: Video?
    @State private var newTitle = ""
    @State private var renameError: String?
    /// New videos not yet played, with the words each needs to reach about 90%: their rows offer the next steps.
    @State private var unwatched: Set<Int64> = []
    @State private var goals: [Int64: CoverageGoal] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let playing {
                PlayerView(env: env, video: playing, startAt: startAt, backTitle: (app.returnSection ?? .videos).title) {
                    closePlayer()
                }
                .id(playing.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            } else {
                list.transition(.opacity)
            }
        }
        .task(id: app.pendingPlayback) { await consumePendingPlayback() }
        .onChange(of: app.addVideosPending) { _, pending in
            // Add Videos while a video is open: close it so the drop area is showing.
            if pending, playing != nil { playing = nil; app.returnSection = nil }
        }
        .modal(isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            if let video = info {
                VideoInfoSheet(env: env, video: video, play: { open(video, at: nil) }, rename: { startRename(video) },
                               calibrate: { calibrating = video })
            }
        }
        .modal(isPresented: Binding(get: { calibrating != nil }, set: { if !$0 { calibrating = nil } })) {
            if let video = calibrating { CalibrationSheet(env: env, video: video) }
        }
        .alert("Rename video", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text(renameError ?? "The files on disk keep their names; this changes the title shown here.")
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle(
                    text: "Videos",
                    subtitle: items.isEmpty ? String(localized: "Drop in videos from your Mac. They never leave it.")
                        : inflected("^[\(items.count) video](inflect: true) · \(formatBytes(totalBytes)) on this Mac"))
                ImportSection(env: env, compact: !items.isEmpty)
                if items.isEmpty { firstSteps }
                if let next = nextUp { nextUpCard(next.item, next.coverage) }
                if !items.isEmpty { sortMenu }
                ForEach(orderedItems) { item in
                    row(item)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)), removal: .opacity))
                }
            }
            .padding(Theme.screenPadding)
        }
        .task(id: "\(app.languageCode)-\(app.dataVersion)") { await reload() }
    }

    /// The video to watch next, by fit alone: one you have heard is as good a choice as a new one. Not offered with a
    /// single video, which the list already shows, or when none is within reach.
    private var nextUp: (item: LibraryEntry, coverage: VideoCoverage)? {
        guard items.count > 1, let best = VideoCoverage.nextUp(from: Array(coverages.values.filter { id in items.contains { $0.id == id.videoID } })),
              let item = items.first(where: { $0.id == best.videoID }) else { return nil }
        return (item, best)
    }

    private func nextUpCard(_ item: LibraryEntry, _ coverage: VideoCoverage) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next up").font(Theme.title(17))
                Text(item.video.title).font(Theme.styled(.headline, design: .rounded)).lineLimit(2)
                Text("You know \(Int((coverage.fraction * 100).rounded()))% of its words.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Watch") { open(item.video, at: nil) }
                .buttonStyle(.pill(.primary, compact: true))
                .accessibilityLabel("Watch \(item.video.title)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
    }

    /// Until there is a video: what this is for, and the three things to do.
    private var firstSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The goal: understand more of what you watch").font(Theme.title(17))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)").font(Theme.sized(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 24, height: 24).background(Circle().fill(Theme.ink.opacity(0.1)))
                        .accessibilityHidden(true)
                    Text(text).font(Theme.styled(.body, design: .rounded)).foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1): \(text)")
            }
        }
        .padding(.top, 6)
    }

    private var steps: [String] {
        [String(localized: "Add a video from your Mac, with its subtitle file if it has one."),
         String(localized: "Watch it, and click any word you don't know."),
         String(localized: "Learn the words that would take it to about 90%, then watch more.")]
    }

    /// "Your videos" with the order they are in, and the way to change it.
    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Your videos").font(Theme.title(17))
                Spacer()
                Menu {
                    Picker("Order", selection: $sort) {
                        Text("Newest first").tag("newest")
                        Text("Closest to my level").tag("fit")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(sort == "fit" ? String(localized: "Closest to my level") : String(localized: "Newest first"), systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                .help("Puts first the videos where you know most of the words, but not all")
            }
            // The percentage on each video, said in words once, where it is first met.
            Text("Each video shows how many of its words you already know. Around 90% is comfortable to follow.")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    private func row(_ item: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader(item)
            if unwatched.contains(item.id) { nextSteps(item) }
        }
        .panel()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(item.video, at: nil) }
        .contextMenu {
            Button("Play") { open(item.video, at: nil) }
            Button("Rename…") { startRename(item.video) }
            Button("Get Info…") { info = item.video }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([env.fileURL(for: item.video)])
            }
        }
    }

    private func rowHeader(_ item: LibraryEntry) -> some View {
        HStack(spacing: 14) {
            VideoThumbnailView(url: env.fileURL(for: item.video), duration: item.video.duration)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title).font(Theme.styled(.headline, design: .rounded)).lineLimit(2)
                Text("\(duration(item.video.duration)) · added \(item.video.importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.small).foregroundStyle(Theme.muted)
                CoverageBadge(coverage: coverages[item.id]).padding(.top, 2)
            }
            Spacer()
            Button("Info", systemImage: "info.circle") { info = item.video }
                .accessibilityLabel("Info for \(item.video.title)")
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(Theme.sized(size: 20)).foregroundStyle(Theme.muted)
                .help("Size, location, rename and delete")
            Button("Play", systemImage: "play.circle.fill") { open(item.video, at: nil) }
                .accessibilityLabel("Play \(item.video.title)")
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(Theme.sized(size: 28)).foregroundStyle(Theme.ink)
                .help("Play")
        }
    }

    private func startRename(_ video: Video) {
        newTitle = video.title
        renameError = nil
        renaming = video
    }

    private func saveRename() {
        guard let video = renaming, let id = video.id else { return }
        Task {
            do {
                try await env.database.renameVideo(id: id, to: newTitle)
                renaming = nil
                app.dataChanged()
            } catch LangError.emptyTitle {
                renameError = "A title can't be empty."
                renaming = video   // keep the alert open
            } catch {
                renameError = error.localizedDescription
                renaming = video
            }
        }
    }

    private func reload() async {
        let loaded = (try? await env.database.libraryVideos(language: app.languageCode)) ?? []
        // A video that has just been added settles into the list; the first load and a change of language do not animate.
        let added = !items.isEmpty && loaded.contains { new in !items.contains { $0.id == new.id } }
        if added { withAnimation(Theme.easeOut(0.4)) { items = loaded } } else { items = loaded }
        totalBytes = env.libraryBytes()
        coverages = (try? await env.database.videoCoverage(language: app.languageCode)) ?? [:]
        unwatched = (try? await env.database.unwatchedVideoIDs(language: app.languageCode)) ?? []
        var reach: [Int64: CoverageGoal] = [:]
        for id in unwatched { reach[id] = try? await env.database.wordsToReach(target: 0.90, inVideo: id) }
        goals = reach
    }

    /// What a new video offers before you have played it: tell Kikimi which words you know, or learn the few it needs to
    /// reach about 90%. Playing the video ends the offer.
    private func nextSteps(_ item: LibraryEntry) -> some View {
        let fresh = goals[item.id].map { $0.isReached ? [] : $0.notStarted } ?? []
        return HStack(spacing: 10) {
            Button("Mark the words I know") { calibrating = item.video }
                .buttonStyle(.pill(.secondary, compact: true))
                .help("Go through this video's commonest new words and tick the ones you know. Only those are marked known.")
            if !fresh.isEmpty {
                Button(inflected("Learn ^[\(fresh.count) word](inflect: true) in lessons")) { app.learnInLessons(fresh.map(\.wordID)) }
                    .buttonStyle(.pill(compact: true))
                    .help("Learning these would take the video to about 90% of its words known.")
            }
        }
    }

    /// The list in the chosen order. "Best fit" uses coverage; videos with nothing to judge by go last.
    private var orderedItems: [LibraryEntry] {
        guard sort == "fit" else { return items }
        return items.sorted { a, b in
            switch (coverages[a.id], coverages[b.id]) {
            case (let x?, let y?): VideoCoverage.bestFirst(x, y)
            case (_?, nil): true
            default: false
            }
        }
    }

    /// Back to Videos, or to the screen that sent you here (e.g. Words, with its search and selection intact).
    private func closePlayer() {
        withAnimation(Theme.screenChange(reduceMotion)) {
            playing = nil
            if let back = app.returnSection {
                app.returnSection = nil
                app.section = back
            }
        }
    }

    private func open(_ video: Video, at time: Double?) {
        startAt = time
        withAnimation(Theme.screenChange(reduceMotion)) { playing = video }
    }

    private func consumePendingPlayback() async {
        guard let request = app.pendingPlayback else { return }
        app.pendingPlayback = nil
        if let video = try? await env.database.video(id: request.videoID) {
            open(video, at: request.time)
        }
    }

    private func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Everything stored for one video, with the way to remove it.
private struct VideoInfoSheet: View {
    let env: LangEnvironment
    let video: Video
    let play: () -> Void
    let rename: () -> Void
    let calibrate: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    @State private var details: VideoDetails?
    @State private var goal: CoverageGoal?
    @State private var confirmDelete = false
    @State private var error: String?

    /// Everything above the buttons; it scrolls only if the window is too short to show it all.
    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title).font(Theme.title(22)).lineLimit(2)

            if let goal, goal.current.totalWords > 0 {
                CoverageGoalView(goal: goal, learn: learnInLessons, markKnown: { dismiss(); calibrate() })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            }

            if let details {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 9) {
                    row("Added", video.importedAt.formatted(date: .long, time: .shortened))
                    row("Language", LanguageProfiles.profile(for: video.language)?.displayName ?? video.language)
                    row("Duration", duration(video.duration))
                    row("Subtitle lines", "\(details.subtitleCount)")
                    row("Words found", "\(details.wordCount)")
                    row("Size on disk", details.filesMissing ? String(localized: "Files are missing") : formatBytes(details.totalBytes))
                    if !details.filesMissing {
                        row("   Video", formatBytes(details.videoBytes))
                        if details.audioBytes > 0 { row("   Audio", formatBytes(details.audioBytes)) }
                    }
                    GridRow(alignment: .top) {
                        Text("Location").foregroundStyle(Theme.muted).gridColumnAlignment(.trailing)
                        Text(details.folder.path).textSelection(.enabled).font(Theme.styled(.callout))
                    }
                }
                .panel()
                Text("This is the app's own copy. Your original file, wherever you imported it from, is not touched by the app.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            } else {
                ProgressView()
            }

            if let error { Text(error).font(Theme.small).foregroundStyle(Theme.red) }

        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .vertical) {
                info
                ScrollView { info }
            }
            HStack(spacing: 12) {
                Button("Delete") { confirmDelete = true }.buttonStyle(.pill(.danger, compact: true))
                Button("Rename") { dismiss(); rename() }.buttonStyle(.pill(.secondary, compact: true))
                Spacer()
                Button("Show in Finder") {
                    if let folder = details?.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Button("Play") { dismiss(); play() }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .disabled(details?.filesMissing ?? true)
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .frame(maxHeight: 580)
        .background(Theme.card)
        .fontDesign(.rounded)
        .tint(Theme.ink)
        .task {
            details = try? await env.details(for: video)
            await loadGoal()
        }
        .confirmationDialog("Delete \"\(video.title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from this Mac", role: .destructive) { delete() }
        } message: {
            Text("""
                Removes the app's copy (\(formatBytes(details?.totalBytes ?? 0))) and its ^[\(details?.subtitleCount ?? 0) subtitle line](inflect: true). \
                Words you've started learning or marked known are kept, but their example lines from this video go until you import it again; \
                untouched words found only in this video are removed. \
                Your original file isn't affected. This can't be undone, but you can import the file again.
                """)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.muted).gridColumnAlignment(.trailing)
            Text(value).font(Theme.styled(.body, design: .rounded, weight: .semibold))
        }
    }

    /// What it would take to know 90% of this video's content words (roughly 95% of everything said).
    private func loadGoal() async {
        guard let id = video.id else { return }
        goal = try? await env.database.wordsToReach(target: 0.90, inVideo: id)
    }

    /// Teaches this video's words on the Learn page, where each can be ignored or marked known first.
    private func learnInLessons(_ entries: [CoverageGoal.Entry]) {
        app.learnInLessons(entries.map(\.wordID))
        dismiss()
    }

    private func delete() {
        Task {
            do {
                try await env.deleteVideo(video)
                app.dataChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
