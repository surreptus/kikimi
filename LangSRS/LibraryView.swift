import AppKit
import LangCore
import SwiftUI

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct LibraryView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    @State private var items: [LibraryEntry] = []
    @State private var sizes: [Int64: Int64] = [:]
    @State private var totalBytes: Int64 = 0
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
                PlayerView(env: env, video: playing, startAt: startAt, backTitle: app.returnSection?.rawValue ?? "Library") {
                    closePlayer()
                }
                .id(playing.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            } else {
                list.transition(.opacity)
            }
        }
        .task(id: app.pendingPlayback) { await consumePendingPlayback() }
        .sheet(item: $info) { video in
            VideoInfoSheet(env: env, video: video, play: { open(video, at: nil) }, rename: { startRename(video) })
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
                    text: "Library",
                    subtitle: items.isEmpty ? "Videos you import appear here."
                        : "\(items.count) video\(items.count == 1 ? "" : "s") · \(formatBytes(totalBytes)) on this Mac")
                if items.isEmpty {
                    ContentUnavailableView("No videos yet", systemImage: "film.stack",
                                           description: Text("Videos you import appear here."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle("Library")
        .task(id: "\(app.languageCode)-\(app.dataVersion)") { await reload() }
    }

    private func row(_ item: LibraryEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title).font(.system(.headline, design: .rounded)).lineLimit(2)
                Text("\(duration(item.video.duration)) · \(item.subtitleCount) lines · \(sizes[item.id].map(formatBytes) ?? "…") · added \(item.video.importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Info", systemImage: "info.circle") { info = item.video }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(.system(size: 20)).foregroundStyle(.secondary)
                .help("Size, location, rename and delete")
            Button("Play", systemImage: "play.circle.fill") { open(item.video, at: nil) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(.system(size: 28)).foregroundStyle(Theme.pink)
                .help("Play")
        }
        .duoCard()
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
    }

    /// Back to the Library, or to the screen that sent you here (e.g. Words, with its search and selection intact).
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
    @Environment(\.dismiss) private var dismiss

    @State private var details: VideoDetails?
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title).font(Theme.title(22)).lineLimit(2)

            if let details {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 9) {
                    row("Added", video.importedAt.formatted(date: .long, time: .shortened))
                    row("Language", LanguageProfiles.profile(for: video.language)?.displayName ?? video.language)
                    row("Duration", duration(video.duration))
                    row("Subtitle lines", "\(details.subtitleCount)")
                    row("Words found", "\(details.wordCount)")
                    row("Size on disk", details.filesMissing ? "Files are missing" : formatBytes(details.totalBytes))
                    if !details.filesMissing {
                        row("   Video", formatBytes(details.videoBytes))
                        row("   Audio", formatBytes(details.audioBytes))
                    }
                    GridRow(alignment: .top) {
                        Text("Location").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(details.folder.path).textSelection(.enabled).font(.callout)
                    }
                }
                .duoCard()
                Text("This is the app's own copy. Your original file, wherever you imported it from, is not touched by the app.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            if let error { Text(error).font(.caption).foregroundStyle(Theme.red) }

            HStack(spacing: 12) {
                Button("Delete") { confirmDelete = true }.buttonStyle(.chunky(.danger, compact: true))
                Button("Rename") { dismiss(); rename() }.buttonStyle(.chunky(.secondary, compact: true))
                Spacer()
                Button("Show in Finder") {
                    if let folder = details?.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                .buttonStyle(.chunky(.secondary, compact: true))
                Button("Play") { dismiss(); play() }
                    .buttonStyle(.chunky(.secondary, compact: true))
                    .disabled(details?.filesMissing ?? true)
                Button("Done") { dismiss() }.buttonStyle(.chunky(compact: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Theme.background)
        .fontDesign(.rounded)
        .tint(Theme.pink)
        .task { details = try? await env.details(for: video) }
        .confirmationDialog("Delete \"\(video.title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from this Mac", role: .destructive) { delete() }
        } message: {
            Text("""
                Removes the app's copy (\(formatBytes(details?.totalBytes ?? 0))) and its \(details?.subtitleCount ?? 0) subtitle lines. \
                Words you've started learning or marked known are kept; untouched words found only in this video are removed. \
                Your original file isn't affected. This can't be undone, but you can import the file again.
                """)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(.system(.body, design: .rounded, weight: .semibold))
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
