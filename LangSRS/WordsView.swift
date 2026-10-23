import AppKit
import LangCore
import SwiftUI

extension WordRow {
    /// Sort order for the Status column: untouched first, finished last.
    var statusOrder: Int {
        switch word.status {
        case .new: 0
        case .learning: 1
        case .known: 2
        case .burned: 3
        }
    }
}

struct WordsView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var rows: [WordRow] = []
    @State private var dictionaryHits: [DictionaryEntry] = []
    @State private var sortOrder = [KeyPathComparator(\WordRow.occurrenceCount, order: .reverse)]
    @State private var confirmReset = false
    @State private var message: String?

    private struct LoadKey: Equatable {
        let language: String, search: String, filter: WordStatus?, version: Int
    }

    // Search, filter and selection live in AppState so they survive a trip to the video and back.
    private var search: String { get { app.wordsSearch } nonmutating set { app.wordsSearch = newValue } }
    private var filter: WordStatus? { get { app.wordsFilter } nonmutating set { app.wordsFilter = newValue } }
    private var selection: Set<Int64> { get { app.wordsSelection } nonmutating set { app.wordsSelection = newValue } }
    private var searchBinding: Binding<String> { Binding(get: { app.wordsSearch }, set: { app.wordsSearch = $0 }) }
    private var filterBinding: Binding<WordStatus?> { Binding(get: { app.wordsFilter }, set: { app.wordsFilter = $0 }) }
    private var selectionBinding: Binding<Set<Int64>> { Binding(get: { app.wordsSelection }, set: { app.wordsSelection = $0 }) }

    private var sortedRows: [WordRow] { rows.sorted(using: sortOrder) }
    private var selectedRows: [WordRow] { rows.filter { selection.contains($0.id) } }
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                table
                bulkBar
            }
            if inspectorShown.wrappedValue {
                Rectangle().fill(Theme.line).frame(width: 2)
                inspector
                    .frame(width: 350)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: inspectorShown.wrappedValue)
        .navigationTitle("Words")
        .task(id: LoadKey(language: app.languageCode, search: search, filter: filter, version: app.dataVersion)) {
            await load()
        }
        .onChange(of: app.languageCode) { selection = [] }
        .confirmationDialog("Reset \(selection.count) words?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { apply(.reset) }
        } message: {
            Text("Words being learned or finished lose their review progress and go back to new.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenTitle(text: "Words", subtitle: "Pick words to learn, or mark the ones you already know.")
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.pink).font(.system(size: 14, weight: .bold))
                    TextField("Search words", text: searchBinding)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                    if !search.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
                .frame(maxWidth: .infinity)

                Menu {
                    Picker("Status", selection: filterBinding) {
                        Text("All statuses").tag(WordStatus?.none)
                        ForEach([WordStatus.new, .learning, .known, .burned], id: \.self) {
                            Text($0.rawValue.capitalized).tag(WordStatus?.some($0))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(filter?.rawValue.capitalized ?? "All", systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.button).buttonStyle(.chunky(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()

                Menu("Select") {
                    Button("All \(rows.count) shown") { selection = Set(rows.map(\.id)) }
                    Button("None") { selection = [] }
                    Divider()
                    ForEach([WordStatus.new, .learning, .known], id: \.self) { status in
                        Button("\(status.rawValue.capitalized) words shown") {
                            selection = Set(rows.filter { $0.word.status == status }.map(\.id))
                        }
                    }
                }
                .menuStyle(.button).buttonStyle(.chunky(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.horizontal, Theme.screenPadding).padding(.top, Theme.screenPadding).padding(.bottom, 10)
    }

    // MARK: Table

    private var table: some View {
        Table(sortedRows, selection: selectionBinding, sortOrder: $sortOrder) {
            TableColumn("Word", value: \.word.lemma) { row in
                Text(row.word.lemma).font(.headline)
            }
            TableColumn("Type", value: \.word.pos.rawValue) { row in
                Text(row.word.pos.rawValue).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Seen", value: \.occurrenceCount) { row in
                Text("\(row.occurrenceCount)×").foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            TableColumn("Status", value: \.statusOrder) { row in
                StatusBadge(status: row.word.status)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Next review") { row in
                if let due = row.word.nextReview {
                    Text(due, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 130)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    trimmedSearch.isEmpty && filter == nil ? "No words yet" : "No matches",
                    systemImage: "text.book.closed",
                    description: Text(trimmedSearch.isEmpty && filter == nil ? "Import a video to collect words." : ""))
            }
        }
    }

    // MARK: Bulk actions

    private enum Bulk { case learn, known, reset }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "\(rows.count) words" : "\(selection.count) of \(rows.count) selected")
                .foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button("Reset") {
                if selectedRows.contains(where: { $0.word.status == .learning || $0.word.status == .burned }) {
                    confirmReset = true
                } else {
                    apply(.reset)
                }
            }
            .buttonStyle(.chunky(.secondary, compact: true))
            Button("Mark known") { apply(.known) }.buttonStyle(.chunky(.secondary, compact: true))
            Button("Start learning") { apply(.learn) }.buttonStyle(.chunky(compact: true))
        }
        .disabled(selection.isEmpty)
        .padding(.horizontal, Theme.screenPadding).padding(.vertical, 12)
        .background(Theme.pinkSoft.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 2) }
    }

    private func apply(_ action: Bulk) {
        let ids = Array(selection)
        Task {
            do {
                switch action {
                case .learn:
                    let started = try await env.database.startLearning(wordIDs: ids)
                    let skipped = ids.count - started
                    message = "Started learning \(started) word\(started == 1 ? "" : "s")"
                        + (skipped > 0 ? " (\(skipped) already in progress)" : "")
                case .known:
                    let n = try await env.database.markKnown(wordIDs: ids)
                    message = "Marked \(n) word\(n == 1 ? "" : "s") as known"
                case .reset:
                    let n = try await env.database.markNew(wordIDs: ids)
                    message = "Reset \(n) word\(n == 1 ? "" : "s")"
                }
                app.dataChanged()
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Inspector

    private var inspectorShown: Binding<Bool> {
        Binding(
            get: { !selection.isEmpty || (!trimmedSearch.isEmpty && !dictionaryHits.isEmpty) },
            set: { if !$0 { selection = [] } })
    }

    @ViewBuilder
    private var inspector: some View {
        if selection.count == 1, let row = rows.first(where: { selection.contains($0.id) }) {
            WordDetail(env: env, row: row).id(row.id)
        } else if selection.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(selection.count) words selected").font(.title2.bold())
                ForEach([WordStatus.new, .learning, .known, .burned], id: \.self) { status in
                    let count = selectedRows.filter { $0.word.status == status }.count
                    if count > 0 { HStack { StatusBadge(status: status); Text("\(count)") } }
                }
                Text("Use the buttons below the list to start learning, mark known, or reset them all at once.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dictionary").font(Theme.title(17))
                    ForEach(dictionaryHits) { EntryView(entry: $0, showsReading: app.profile.display.showsReadings) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Loading

    private func load() async {
        let language = app.languageCode
        do {
            rows = try await env.database.words(language: language, search: search, status: filter)
            selection.formIntersection(rows.map(\.id))
            dictionaryHits = trimmedSearch.isEmpty
                ? [] : try await env.database.lookup(language: language, term: trimmedSearch, limit: 5)
        } catch {
            rows = []
            dictionaryHits = []
        }
    }
}

private struct WordDetail: View {
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
                actions
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

    /// The word, its status, and a ⋯ menu for the less common things.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.word.lemma).font(Theme.title(32)).lineLimit(2).minimumScaleFactor(0.6)
                StatusBadge(status: row.word.status)
                Spacer(minLength: 8)
                Menu {
                    if !examples.isEmpty {
                        Button("Export audio clips…") { exportExamples(.audio) }
                        Button("Export video clips…") { exportExamples(.video) }
                        Divider()
                    }
                    Button("Reset to new", role: .destructive) { Task { await change { try await env.database.markNew(wordID: row.id) } } }
                        .disabled(row.word.status == .new)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .heavy))
                        .frame(width: 32, height: 28)
                }
                .menuStyle(.button).buttonStyle(.chunky(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                .help("More: export example clips, reset")
            }
            if let stage = row.word.stage {
                Text("Stage \(stage.rawValue) of 9").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Two equal, roomy buttons; whichever doesn't apply is simply left out.
    private var actions: some View {
        HStack(spacing: 10) {
            if row.word.status != .learning {
                Button("Start learning") { Task { await change { try await env.database.startLearning(wordID: row.id) } } }
                    .buttonStyle(.chunky(.primary, compact: true, fullWidth: true))
            }
            if row.word.status != .known {
                Button("Mark known") { Task { await change { try await env.database.markKnown(wordID: row.id) } } }
                    .buttonStyle(.chunky(.secondary, compact: true, fullWidth: true))
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

    private func change(_ work: () async throws -> Void) async {
        try? await work()
        app.dataChanged()
    }

    private func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct EntryView: View {
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

private struct StatusBadge: View {
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
