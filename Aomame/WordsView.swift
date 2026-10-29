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
        case .finished: 3
        }
    }
}

struct WordsView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var rows: [WordRow] = []
    @State private var dictionaryHits: [DictionaryEntry] = []
    @State private var sort = WordSort(column: .seen, ascending: false)
    @State private var confirmReset = false
    @State private var chooseAnki = false
    @State private var ankiResult: AnkiExportResult?
    @FocusState private var searchFocused: Bool
    @State private var message: String?

    private struct LoadKey: Equatable {
        let language: String, search: String, filter: WordStatus?, type: PartOfSpeech?, version: Int
    }

    // Search, filter and selection live in AppState so they survive a trip to the video and back.
    private var search: String { get { app.wordsSearch } nonmutating set { app.wordsSearch = newValue } }
    private var filter: WordStatus? { get { app.wordsFilter } nonmutating set { app.wordsFilter = newValue } }
    private var selection: Set<Int64> { get { app.wordsSelection } nonmutating set { app.wordsSelection = newValue } }
    private var searchBinding: Binding<String> { Binding(get: { app.wordsSearch }, set: { app.wordsSearch = $0 }) }
    private var filterBinding: Binding<WordStatus?> { Binding(get: { app.wordsFilter }, set: { app.wordsFilter = $0 }) }
    private var typeFilter: PartOfSpeech? { app.wordsTypeFilter }
    private var typeBinding: Binding<PartOfSpeech?> { Binding(get: { app.wordsTypeFilter }, set: { app.wordsTypeFilter = $0 }) }
    /// The types of word this language keeps (nouns, verbs...), in a fixed order. Particles and other small words
    /// aren't kept, so they aren't offered.
    private var typeChoices: [PartOfSpeech] {
        [.noun, .verb, .adjective, .adverb, .other].filter { app.profile.contentPOS.contains($0) }
    }
    /// What the filter button says: "All", or what is narrowing the list.
    private var filterSummary: String {
        let parts = [filter?.title, typeFilter?.title].compactMap { $0 }
        return parts.isEmpty ? String(localized: "All") : parts.joined(separator: " · ")
    }
    /// "New words shown": selects every word with that status in the current list.
    private func shownLabel(_ status: WordStatus) -> String {
        switch status {
        case .new: String(localized: "New words shown")
        case .learning: String(localized: "Learning words shown")
        case .known: String(localized: "Known words shown")
        case .finished: String(localized: "Finished words shown")
        }
    }
    private var selectionBinding: Binding<Set<Int64>> { Binding(get: { app.wordsSelection }, set: { app.wordsSelection = $0 }) }

    private var sortedRows: [WordRow] { rows.sorted(using: sort.comparators) }
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
                Rectangle().fill(Theme.line).frame(width: 1)
                inspector
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: inspectorShown.wrappedValue)
        .task(id: LoadKey(language: app.languageCode, search: search, filter: filter, type: typeFilter, version: app.dataVersion)) {
            await load()
        }
        .onChange(of: app.languageCode) { selection = [] }
        .onChange(of: app.findWordsPending) { _, pending in if pending { focusSearch() } }
        .task { if app.findWordsPending { focusSearch() } }
        .confirmationDialog("Export to Anki", isPresented: $chooseAnki) {
            Button("Export with sentence audio") { exportAnki(includeAudio: true) }
            Button("Export text only") { exportAnki(includeAudio: false) }
        } message: {
            Text(selection.isEmpty
                 ? "Exports the words you are learning, each with its meaning and a sentence from your videos. Sentence audio makes a media folder you copy into Anki once."
                 : "Exports the \(selection.count) selected words, each with its meaning and a sentence from your videos. Sentence audio makes a media folder you copy into Anki once.")
        }
        .alert("Anki file saved", isPresented: Binding(get: { ankiResult != nil }, set: { if !$0 { ankiResult = nil } })) {
            if let ankiResult {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ankiResult.file]) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let ankiResult { Text(ankiMessage(ankiResult)) }
        }
        .confirmationDialog("Reset \(selection.count) words?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { apply(.reset) }
        } message: {
            Text("Words being learned or finished lose their review progress and go back to new.")
        }
    }

    /// The selection summary counts words by status, not stage, so it uses a plain dot rather than the stage ring.
    private func summaryColor(_ status: WordStatus) -> Color {
        switch status {
        case .new: Theme.muted
        case .learning: Theme.orange
        case .known: Theme.green
        case .finished: Theme.ink
        }
    }

    private func focusSearch() {
        app.findWordsPending = false
        searchFocused = true
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenTitle(text: "Words", subtitle: "Pick words to learn, or mark the ones you already know.")
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink).font(.system(size: 14, weight: .bold))
                    TextField("Search words", text: searchBinding)
                        .focused($searchFocused)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                    if !search.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
                .frame(maxWidth: .infinity)

                Menu {
                    Picker("Status", selection: filterBinding) {
                        Text("All statuses").tag(WordStatus?.none)
                        ForEach([WordStatus.new, .learning, .known, .finished], id: \.self) {
                            Text($0.title).tag(WordStatus?.some($0))
                        }
                    }
                    .pickerStyle(.inline)
                    Picker("Type", selection: typeBinding) {
                        Text("All types").tag(PartOfSpeech?.none)
                        ForEach(typeChoices, id: \.self) { Text($0.title).tag(PartOfSpeech?.some($0)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(filterSummary, systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()

                Menu("Select") {
                    Button("All \(rows.count) shown") { selection = Set(rows.map(\.id)) }
                    Button("None") { selection = [] }
                    Divider()
                    ForEach([25, 50, 100, 250], id: \.self) { n in
                        Button("\(n) most-seen new words") { selectMostSeenNew(n) }
                    }
                    Divider()
                    ForEach([WordStatus.new, .learning, .known], id: \.self) { status in
                        Button(shownLabel(status)) {
                            selection = Set(rows.filter { $0.word.status == status }.map(\.id))
                        }
                    }
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.horizontal, Theme.screenPadding).padding(.top, Theme.screenPadding).padding(.bottom, 10)
    }

    // MARK: Table

    private var table: some View {
        WordTable(rows: sortedRows, selection: selectionBinding, sort: $sort)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if rows.isEmpty {
                if trimmedSearch.isEmpty && filter == nil && typeFilter == nil {
                    EmptyState(title: "No words yet", message: "Add a video on the Videos page to collect words.", illustration: .bubble)
                } else {
                    EmptyState(title: "No matches", message: "Try a different search or status.")
                }
            }
        }
    }

    // MARK: Bulk actions

    private enum Bulk { case learn, known, reset }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "\(rows.count) words" : "\(selection.count) of \(rows.count) selected")
                .foregroundStyle(Theme.muted)
            if let message { Text(message).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1) }
            Spacer()
            // Works with nothing selected too: it then exports the words you are learning.
            Button("Export to Anki…") { chooseAnki = true }
                .buttonStyle(.pill(.secondary, compact: true))
                .help("Make a file Anki can import (File > Import), from the selected words or the ones you are learning")
            HStack(spacing: 10) {
                Button("Reset") {
                    if selectedRows.contains(where: { $0.word.status == .learning || $0.word.status == .finished }) {
                        confirmReset = true
                    } else {
                        apply(.reset)
                    }
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Button("Mark known") { apply(.known) }.buttonStyle(.pill(.secondary, compact: true))
                Button("Start learning") { apply(.learn) }.buttonStyle(.pill(compact: true))
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, Theme.screenPadding).padding(.vertical, 12)
        .background(Theme.soft.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func exportAnki(includeAudio: Bool) {
        guard let folder = ExportPanels.chooseFolder(message: String(localized: "Choose a folder for the Anki file")) else { return }
        message = String(localized: "Exporting…")
        Task {
            do {
                let ids = selection.isEmpty
                    ? try await env.database.learningWordIDs(language: app.languageCode)
                    : sortedRows.filter { selection.contains($0.id) }.map(\.id)
                guard !ids.isEmpty else { message = String(localized: "No words to export."); return }
                ankiResult = try await env.exportAnki(wordIDs: ids, language: app.languageCode, includeAudio: includeAudio, into: folder)
                message = nil
            } catch {
                message = String(localized: "Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func ankiMessage(_ result: AnkiExportResult) -> String {
        var text = String(localized: "Saved \(inflected("^[\(result.cards) card](inflect: true)")) to \(result.file.deletingLastPathComponent().lastPathComponent). In Anki, choose File > Import and pick \(result.file.lastPathComponent).")
        if result.audioFiles > 0 {
            text += " " + String(localized: "Copy the files in the media folder into Anki's collection.media folder first, so the sentence audio plays.")
        }
        return text
    }

    /// The words you meet most that you haven't touched yet: the best ones to start learning.
    private func selectMostSeenNew(_ count: Int) {
        selection = Set(rows.filter { $0.word.status == .new }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(count).map(\.id))
    }

    private func apply(_ action: Bulk) {
        let ids = Array(selection)
        Task {
            do {
                switch action {
                case .learn:
                    let started = try await env.database.startLearning(wordIDs: ids)
                    let skipped = ids.count - started
                    message = inflected("Started learning ^[\(started) word](inflect: true)")
                        + (skipped > 0 ? " (\(skipped) already in progress)" : "")
                case .known:
                    let n = try await env.database.markKnown(wordIDs: ids)
                    message = inflected("Marked ^[\(n) word](inflect: true) as known")
                case .reset:
                    let n = try await env.database.markNew(wordIDs: ids)
                    message = inflected("Reset ^[\(n) word](inflect: true)")
                }
                app.dataChanged()
            } catch {
                message = String(localized: "Failed: \(error.localizedDescription)")
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
                ForEach([WordStatus.new, .learning, .known, .finished], id: \.self) { status in
                    let count = selectedRows.filter { $0.word.status == status }.count
                    if count > 0 { HStack { StatusPill(text: status.title, color: summaryColor(status)); Text("\(count)") } }
                }
                Text("Use the buttons below the list to start learning, mark known, or reset them all at once.")
                    .font(.callout).foregroundStyle(Theme.muted)
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
        rows = await env.searchWords(search, profile: app.profile, status: filter, pos: typeFilter)
        selection.formIntersection(rows.map(\.id))
        dictionaryHits = trimmedSearch.isEmpty
            ? [] : await env.lookupWord(trimmedSearch, profile: app.profile, limit: 5)
    }
}
