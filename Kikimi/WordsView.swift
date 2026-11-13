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
        case .ignored: 4
        }
    }
}

struct WordsView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var rows: [WordRow] = []
    @State private var dictionaryHits: [DictionaryEntry] = []
    @State private var sort = WordSort(column: .seen, ascending: false)
    @FocusState private var searchFocused: Bool

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
    /// The types of word this language keeps (nouns, verbs...), in a fixed order. Particles and most other small words
    /// aren't kept, so they aren't offered.
    private var typeChoices: [PartOfSpeech] {
        [.noun, .verb, .adjective, .adverb, .conjunction, .other].filter { app.profile.contentPOS.contains($0) }
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
        case .ignored: String(localized: "Ignored words shown")
        }
    }
    private var selectionBinding: Binding<Set<Int64>> { Binding(get: { app.wordsSelection }, set: { app.wordsSelection = $0 }) }

    private var sortedRows: [WordRow] { rows.sorted(using: sort.comparators) }
    /// No words in this language at all (not just none that match a search or filter).
    private var noWordsYet: Bool { rows.isEmpty && trimmedSearch.isEmpty && filter == nil && typeFilter == nil }
    private var selectedRows: [WordRow] { rows.filter { selection.contains($0.id) } }
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            if noWordsYet {
                // Nothing to search, sort or select yet: only where words come from.
                ScreenTitle(text: "Words", subtitle: "Pick words to learn, or mark the ones you already know.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenPadding).padding(.top, Theme.screenPadding)
                EmptyState(title: "No words yet", message: "Add a video on the Videos page to collect words.", illustration: .bubble,
                           actionTitle: "Go to Videos", action: { app.select(.videos) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                table
                // Nothing to act on until a word is selected.
                if !selection.isEmpty { bulkBar }
            }
        }
        .sidePanel(isPresented: inspectorShown.wrappedValue) { inspector }
        .task(id: LoadKey(language: app.languageCode, search: search, filter: filter, type: typeFilter, version: app.dataVersion)) {
            await load()
        }
        .onChange(of: app.languageCode) { selection = [] }
        .onChange(of: app.findWordsPending) { _, pending in if pending { focusSearch() } }
        .task { if app.findWordsPending { focusSearch() } }
    }

    /// The selection summary counts words by status, not stage, so it uses a plain dot rather than the stage ring.
    private func summaryColor(_ status: WordStatus) -> Color {
        switch status {
        case .new: Theme.muted
        case .learning: Theme.orange
        case .known: Theme.green
        case .finished: Theme.ink
        case .ignored: Theme.muted
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
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink).font(Theme.sized(size: 14, weight: .bold))
                    TextField("Search words", text: searchBinding)
                        .focused($searchFocused)
                        .textFieldStyle(.plain)
                        .font(Theme.styled(.body, design: .rounded))
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
                        ForEach([WordStatus.new, .learning, .known, .finished, .ignored], id: \.self) {
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
                Text(inflected("^[\(rows.count) word](inflect: true)")).font(Theme.small).foregroundStyle(Theme.muted).fixedSize()
            }
        }
        .padding(.horizontal, Theme.screenPadding).padding(.top, Theme.screenPadding).padding(.bottom, 10)
    }

    // MARK: Table

    private var table: some View {
        WordTable(rows: sortedRows, selection: selectionBinding, sort: $sort)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if rows.isEmpty { EmptyState(title: "No matches", message: "Try a different search or status.") }
        }
    }

    // MARK: Bulk actions

    private enum Bulk { case learn, known, reset, ignore }

    /// The words in the selection an action would change: Learn starts only new words, Known skips ones already known or set
    /// aside, Ignore skips ones already ignored, and Reset skips new ones.
    private func ids(for action: Bulk) -> [Int64] {
        selectedRows.filter { row in
            switch action {
            case .learn: row.word.status == .new
            case .known: [.new, .learning, .finished].contains(row.word.status)
            case .ignore: row.word.status != .ignored
            case .reset: row.word.status != .new
            }
        }.map(\.id)
    }

    /// Shown only while words are selected, and each button only when it would change one of them.
    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) of \(rows.count) selected").foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 10) {
                if !ids(for: .reset).isEmpty {
                    Button("Reset") { apply(.reset) }
                        .buttonStyle(.pill(.quiet, compact: true))
                        .help("Back to a new word, so it can be learned from the start")
                }
                if !ids(for: .ignore).isEmpty {
                    Button("Ignore") { apply(.ignore) }
                        .buttonStyle(.pill(.quiet, compact: true))
                        .help("Set aside words that are not worth learning, such as names or mistakes. They stay, and Reset brings them back.")
                }
                if !ids(for: .known).isEmpty {
                    Button("Known") { apply(.known) }.buttonStyle(.pill(.secondary, compact: true))
                }
                if !ids(for: .learn).isEmpty {
                    Button("Learn") { apply(.learn) }.buttonStyle(.pill(compact: true))
                }
            }
        }
        .padding(.horizontal, Theme.screenPadding).padding(.vertical, 12)
        .background(Theme.soft.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// The words you meet most that you haven't touched yet: the best ones to start learning.
    private func selectMostSeenNew(_ count: Int) {
        selection = Set(rows.filter { $0.word.status == .new }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(count).map(\.id))
    }

    private func apply(_ action: Bulk) {
        var ids = ids(for: action)
        guard !ids.isEmpty else { return }
        Task {
            do {
                let wanted = ids.count
                var perDay = 0
                if action == .learn {
                    // Learn follows the day's new-word allowance, like the lessons, so one click cannot start a pile of reviews.
                    perDay = env.dailyLessons.perDay(for: app.profile)
                    if let room = try await env.database.newWordRoom(language: app.languageCode, perDay: perDay) {
                        ids = try await env.database.mostSeen(ids, count: room)   // as the lessons choose
                    }
                    guard !ids.isEmpty else {
                        app.showToast(inflected("No words started. Today's limit is ^[\(perDay) new word](inflect: true), and it is used up. You can change the limit in Settings."))
                        return
                    }
                }
                let before = try await env.database.snapshot(of: ids)   // so Undo can put each word back as it was
                let text: String
                switch action {
                case .learn:
                    let n = try await env.database.startLearning(wordIDs: ids)
                    text = ids.count < wanted
                        ? inflected("Started learning \(n) of \(wanted) words. Today's limit is ^[\(perDay) new word](inflect: true). They are ready on the Learn page.")
                        : inflected("Started learning ^[\(n) word](inflect: true). They are ready on the Learn page.")
                case .known:
                    let n = try await env.database.markKnown(wordIDs: ids)
                    text = inflected("Marked ^[\(n) word](inflect: true) as known")
                case .ignore:
                    let n = try await env.database.markIgnored(wordIDs: ids)
                    text = inflected("Ignored ^[\(n) word](inflect: true). Show them with the Ignored status filter.")
                case .reset:
                    let n = try await env.database.markNew(wordIDs: ids)
                    text = inflected("Reset ^[\(n) word](inflect: true)")
                }
                app.dataChanged()
                app.showToast(text, undo: (String(localized: "Undo"), { undo(before) }))
            } catch {
                app.showToast(Problem(error, fallback: String(localized: "Kikimi couldn't change those words. Try again.")))
            }
        }
    }

    private func undo(_ before: [Word]) {
        Task {
            do {
                try await env.database.restore(before)
                app.dataChanged()
                app.showToast(String(localized: "Undone"))
            } catch {
                app.showToast(Problem(error, fallback: String(localized: "Kikimi couldn't undo that. Try again.")))
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
            WordDetail(env: env, row: row)
        } else if selection.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(selection.count) words selected").font(Theme.styled(.title2, weight: .bold))
                ForEach([WordStatus.new, .learning, .known, .finished, .ignored], id: \.self) { status in
                    let count = selectedRows.filter { $0.word.status == status }.count
                    if count > 0 { HStack { StatusPill(text: status.title, color: summaryColor(status)); Text("\(count)") } }
                }
                Text("Use the buttons below the list to learn, mark as known, or reset them all at once.")
                    .font(Theme.styled(.callout)).foregroundStyle(Theme.muted)
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
