import AppKit
import LangCore
import SwiftUI

struct WordDetail: View {
    let env: LangEnvironment
    let row: WordRow
    @Environment(AppState.self) private var app
    @State private var entries: [DictionaryEntry] = []
    @State private var examples: [ExampleLine] = []
    @State private var exportMessage: String?
    @State private var audio: SentenceAudioPlayer?
    @State private var playingLine: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }

                Text("Dictionary").font(Theme.title(17))
                if entries.isEmpty {
                    Text("No entry found.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { EntryView(entry: $0, showsReading: app.profile.display.showsReadings) }
                }

                Text("From your videos").font(Theme.title(17))
                ForEach(examples) { line in exampleRow(line) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            audio = SentenceAudioPlayer(libraryRoot: env.libraryURL)
            entries = (try? await env.database.lookup(language: row.word.language, term: row.word.lemma, limit: 5)) ?? []
            examples = (try? await env.database.examples(wordID: row.id)) ?? []
        }
        .onChange(of: audio?.isPlaying) { _, playing in if playing != true { playingLine = nil } }
        .onDisappear { audio?.stop() }
    }

    /// The word and its status, with a ⋯ menu to export its example clips.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.word.lemma).font(Theme.title(32)).lineLimit(2).minimumScaleFactor(0.6)
                StatusBadge(status: row.word.status)
                Spacer(minLength: 8)
                if !examples.isEmpty {
                    Menu {
                        Button("Export audio clips…") { exportExamples(.audio) }
                        Button("Export video clips…") { exportExamples(.video) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .heavy))
                            .frame(width: 32, height: 28)
                    }
                    .menuStyle(.button).buttonStyle(.chunky(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                    .help("Export this word's example sentences as clips")
                }
            }
            if let stage = row.word.stage {
                Text("Stage \(stage.rawValue) of 9").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func exampleRow(_ line: ExampleLine) -> some View {
        let isPlaying = playingLine == line.id
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.text).font(.system(.body, design: .rounded)).textSelection(.enabled)
                Text("\(line.videoTitle) · \(timestamp(line.startTime))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button(isPlaying ? "Stop" : "Hear this line", systemImage: isPlaying ? "stop.fill" : "speaker.wave.2.fill") {
                togglePlayback(line)
            }
            .buttonStyle(.chunky(isPlaying ? .primary : .secondary, compact: true))
            .labelStyle(.iconOnly)
            .help("Play this sentence's audio from your video, right here")
            Button("Open in video", systemImage: "play.rectangle.fill") {
                audio?.stop()
                app.openVideo(id: line.videoID, at: line.startTime)
            }
            .buttonStyle(.chunky(.secondary, compact: true))
            .labelStyle(.iconOnly)
            .help("Open the video at this moment")
        }
        .padding(.vertical, 2)
    }

    private func togglePlayback(_ line: ExampleLine) {
        guard let audio else { return }
        if playingLine == line.id {
            audio.stop()
            playingLine = nil
            return
        }
        playingLine = line.id
        Task {
            if await !audio.play(line) {
                playingLine = nil
                exportMessage = "That audio file is missing from the library."
            }
        }
    }

    private func exportExamples(_ kind: ClipKind) {
        guard let folder = ExportPanels.chooseFolder(message: "Choose a folder for the \(row.word.lemma) clips") else { return }
        exportMessage = "Exporting…"
        Task {
            do {
                let files = try await env.exportClips(forWord: row.id, kind: kind, into: folder)
                exportMessage = "Saved \(files.count) clip\(files.count == 1 ? "" : "s") to \(folder.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct EntryView: View {
    let entry: DictionaryEntry
    let showsReading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.headword).font(.headline)
                if showsReading, let reading = entry.reading, reading != entry.headword {
                    Text(reading).foregroundStyle(.secondary)
                }
            }
            Text(entry.gloss).font(.callout).textSelection(.enabled)
        }
    }
}

struct StatusBadge: View {
    let status: WordStatus

    var body: some View { StatusPill(text: status.rawValue, color: color) }

    private var color: Color {
        switch status {
        case .new: .secondary
        case .learning: Theme.orange
        case .known: Theme.green
        case .burned: Theme.purple
        }
    }
}
