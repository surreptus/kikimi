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
    @State private var sizes: [Int64: Int64] = [:]
    @State private var totalBytes: Int64 = 0
    @State private var coverages: [Int64: VideoCoverage] = [:]
    /// "newest" or "fit": how the list is ordered. Best fit puts the videos you can most comfortably follow first.
    @AppStorage("videoSort") private var sort = "newest"
    @State private var playing: Video?
    @State private var startAt: Double?
    @State private var info: Video?
    @State private var renaming: Video?
    @State private var newTitle = ""
    @State private var renameError: String?
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
                VideoInfoSheet(env: env, video: video, play: { open(video, at: nil) }, rename: { startRename(video) })
            }
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
                    subtitle: items.isEmpty ? String(localized: "Drop videos you own. They never leave this Mac.")
                        : inflected("^[\(items.count) video](inflect: true) · \(formatBytes(totalBytes)) on this Mac"))
                ImportSection(env: env)
                if items.isEmpty {
                    VStack(spacing: 8) {
                        EmptyState(title: "No videos yet", message: "Drop one above and its words will appear on the Words page.",
                                   illustration: .clapperboard)
                        Button("How Kikimi works") { app.showAbout = true }.buttonStyle(.pill(.secondary, compact: true))
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    sortMenu
                }
                ForEach(orderedItems) { item in
                    row(item)
                }
            }
            .padding(Theme.screenPadding)
        }
        .task(id: "\(app.languageCode)-\(app.dataVersion)") { await reload() }
    }

    /// "Your videos" with the order they are in, and the way to change it.
    private var sortMenu: some View {
        HStack {
            Text("Your videos").font(Theme.title(17))
            Spacer()
            Menu {
                Picker("Order", selection: $sort) {
                    Text("Newest first").tag("newest")
                    Text("Best fit first").tag("fit")
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort == "fit" ? String(localized: "Best fit first") : String(localized: "Newest first"), systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
            .help("Best fit puts the videos you already know most of, but not all, first")
        }
        .padding(.top, 8)
    }

    private func row(_ item: LibraryEntry) -> some View {
        HStack(spacing: 14) {
            VideoThumbnailView(url: env.fileURL(for: item.video), duration: item.video.duration)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title).font(.system(.headline, design: .rounded)).lineLimit(2)
                Text("\(duration(item.video.duration)) · ^[\(item.subtitleCount) line](inflect: true) · \(sizes[item.id].map(formatBytes) ?? "…") · added \(item.video.importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.small).foregroundStyle(Theme.muted)
                CoverageBadge(coverage: coverages[item.id]).padding(.top, 2)
            }
            Spacer()
            Button("Info", systemImage: "info.circle") { info = item.video }
                .accessibilityLabel("Info for \(item.video.title)")
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(.system(size: 20)).foregroundStyle(Theme.muted)
                .help("Size, location, rename and delete")
            Button("Play", systemImage: "play.circle.fill") { open(item.video, at: nil) }
                .accessibilityLabel("Play \(item.video.title)")
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(.system(size: 28)).foregroundStyle(Theme.ink)
                .help("Play")
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
        items = (try? await env.database.libraryVideos(language: app.languageCode)) ?? []
        sizes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, env.bytesOnDisk(for: $0.video)) })
        totalBytes = env.libraryBytes()
        coverages = (try? await env.database.videoCoverage(language: app.languageCode)) ?? [:]
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
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    @State private var details: VideoDetails?
    @State private var goal: CoverageGoal?
    @State private var goalMessage: String?
    @State private var confirmDelete = false
    @State private var error: String?

    /// Everything above the buttons; it scrolls only if the window is too short to show it all.
    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title).font(Theme.title(22)).lineLimit(2)

            if let goal, goal.current.totalWords > 0 {
                CoverageGoalView(goal: goal, startLearning: startLearning, message: goalMessage)
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
                        Text(details.folder.path).textSelection(.enabled).font(.callout)
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
                Words you've started learning or marked known are kept; untouched words found only in this video are removed. \
                Your original file isn't affected. This can't be undone, but you can import the file again.
                """)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.muted).gridColumnAlignment(.trailing)
            Text(value).font(.system(.body, design: .rounded, weight: .semibold))
        }
    }

    /// What it would take to know 90% of this video's content words (roughly 95% of everything said).
    private func loadGoal() async {
        guard let id = video.id else { return }
        goal = try? await env.database.wordsToReach(target: 0.90, inVideo: id)
    }

    private func startLearning(_ entries: [CoverageGoal.Entry]) {
        Task {
            do {
                let added = try await env.database.startLearning(wordIDs: entries.map(\.wordID))
                app.dataChanged()
                await loadGoal()
                goalMessage = inflected("Added ^[\(added) word](inflect: true) to your reviews.")
            } catch {
                self.error = error.localizedDescription
            }
        }
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
