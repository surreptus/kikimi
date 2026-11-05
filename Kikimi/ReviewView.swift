import LangCore
import SwiftUI

struct ReviewView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var overview: ReviewOverview?
    @State private var stats: LearningStats?
    @State private var session: ReviewSession?
    @State private var card: ReviewCard?
    @State private var revealed = false
    @State private var remaining = 0
    @State private var total = 0
    @State private var summary: (answered: Int, correct: Int)?
    @State private var error: String?
    @State private var audio: SentenceAudioPlayer?
    @State private var mode: SentenceAudioMode = .onReveal
    @State private var style: ReviewStyle = .meaning
    /// A check of words marked known: the summary says what was missed and sent back to learning.
    /// Which extra study is under way, or nil in a normal review.
    @State private var extra: ExtraStudy?
    @State private var returned = 0
    /// The word's own page beside the card, opened from the revealed answer (never before: it would show the meaning).
    @State private var showsWord = false
    @State private var wordNow: Word?
    /// Typing what you hear: what was typed, and how it compared once checked.
    @State private var typed = ""
    @State private var dictationResult: DictationCheck?
    @FocusState private var typingFocused: Bool
    /// The sentence being corrected, and how long its video is (the editor's limit for the end time).
    @State private var editingExample: ExampleLine?
    @State private var editingDuration = 0.0
    /// The sentence's translation, shown on the answer when asked for (or always, in Settings).
    /// nil is the default for the card (shown in a listening card, or as Settings says); T sets it either way.
    @State private var translationChoice: Bool?
    @State private var translations: LineTranslations?
    @State private var translationsVideo: Int64?

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Review failed", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let card {
                cardWithWord(card)
            } else if let summary {
                VStack(spacing: 0) {
                    finished(summary).padding(.top, 28)
                    if let overview, !overview.isEmpty { ReviewOverviewView(overview: overview, stats: stats, style: styleChoice, start: { startSession() }, practise: { startSession(extra: $0) }) }
                }
            } else if let overview {
                if overview.isEmpty {
                    EmptyState(title: "Nothing to review yet", message: "Choose words to learn on the Words page, then come back.",
                               actionTitle: "Go to Words", action: { app.select(.words) })
                } else {
                    ReviewOverviewView(overview: overview, stats: stats, style: styleChoice, start: { startSession() }, practise: { startSession(extra: $0) })
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: mode) { _, new in env.reviewAudio.setMode(new, for: app.profile) }
        .task(id: app.languageCode) { await loadOverview() }
        .task(id: app.dataVersion) { if card == nil { await loadOverview(keepingSummary: true) } }
        .task(id: app.languageCode) { style = env.reviewStyle.style(for: app.profile) }
        .onDisappear { audio?.stop() }
    }

    private func finished(_ summary: (answered: Int, correct: Int)) -> some View {
        VStack(spacing: 12) {
            Text(extra == nil ? "All done for now" : "Practice done").font(Theme.title(30))
            Text(summaryText(summary))
                .font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted)
            if extra == .known, returned > 0 {
                Text(inflected("^[\(returned) word](inflect: true) went back to your reviews, so each video's coverage no longer counts it as known."))
                    .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }
    }

    private func summaryText(_ summary: (answered: Int, correct: Int)) -> String {
        switch extra {
        case nil: String(localized: "\(summary.correct) of \(summary.answered) answers right the first time.")
        case .known: String(localized: "You knew \(summary.correct) of \(summary.answered) of the words you marked known.")
        case .ahead, .finished: String(localized: "You got \(summary.correct) of \(summary.answered) right. Nothing moved: these words keep their schedule.")
        }
    }

    /// The card, with the word's page beside it once asked for.
    private func cardWithWord(_ card: ReviewCard) -> some View {
        cardView(card)
        .task(id: "\(card.id)-\(translationVisible)-\(card.example?.text ?? "")") { await loadTranslation() }
        .sheet(item: $editingExample) { example in
            EditLineSheet(
                line: Subtitle(id: example.id, videoId: example.videoID, idx: 0, startTime: example.startTime,
                               endTime: example.endTime, text: example.text),
                duration: editingDuration, profile: app.profile, env: env,
                preview: { start, end in Task { await audio?.play(example.edited(start: start, end: end)) } },
                saved: { saved in
                    translations?.forget(example.id)   // it was of the old text
                    self.card = card.showing(example.edited(text: saved.text, start: saved.startTime, end: saved.endTime))
                    editingExample = nil
                    app.dataChanged()
                }, cancel: { audio?.stop(); editingExample = nil })
        }
        .sidePanel(isPresented: showsWord && revealed) {
            WordDetail(env: env, row: WordRow(word: wordNow ?? card.word)).id(card.id)
        }
        .onChange(of: app.dataVersion) {
            // Learn or Known in the page changes the word; show it as it is now.
            guard showsWord, let id = card.word.id else { return }
            Task { wordNow = try? await env.database.word(id: id) }
        }
    }

    /// The word, which opens its page once the answer is showing.
    @ViewBuilder
    private func lemmaText(_ card: ReviewCard, font: Font) -> some View {
        if revealed {
            Button { showsWord.toggle() } label: { Text(lemmaLabel(card)).font(font) }
                .buttonStyle(.plain)
                .keyboardShortcut("i", modifiers: [])
                .help(showsWord ? "Hide this word's page (I)" : "Show everything about this word (I)")
                .accessibilityHint("Shows this word's page")
        } else {
            Text(card.word.lemma).font(font)
        }
    }

    /// With the answer showing, a noun appears with its article ("das Buch"): the gender is part of what to learn.
    private func lemmaLabel(_ card: ReviewCard) -> String {
        guard card.word.pos == .noun else { return card.word.lemma }
        return card.entries.nounPhrase(using: app.profile) ?? card.word.lemma
    }

    private func cardView(_ card: ReviewCard) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Button("End session", systemImage: "xmark") { endSession() }
                    .labelStyle(.pillIcon).buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Back to the overview (Esc). Your answers so far are kept.")
                ProgressView(value: Double(max(0, total - remaining)), total: Double(max(1, total)))
                    .progressViewStyle(.thin)
                Text("\(remaining) left").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                // In the page, not the window toolbar: a toolbar item here changes how the title bar looks on this screen only.
                Menu {
                    Picker("Play the sentence", selection: $mode) {
                        ForEach(SentenceAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .medium)).frame(width: PillIconStyle.width)
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                .help("When to play the sentence audio")
            }
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if let cloze = cloze(for: card) {
                    clozeFace(cloze, card)
                } else if listening(for: card) {
                    listenFace(card)
                } else if dictation(for: card) {
                    dictationFace(card)
                } else {
                lemmaText(card, font: .system(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.title)

                // The word as it was said in your video: the context is part of the question, the translation is not.
                if let example = card.example {
                    Text(highlighted(example)).font(.system(.body, design: .rounded)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                if revealed {
                    VStack(spacing: 10) {
                        if app.profile.display.showsReadings, let reading = readings(of: card) {
                            Text(reading).font(Theme.title(22)).foregroundStyle(Theme.ink)
                        }
                        Text(card.entries.first?.gloss ?? "No dictionary entry")
                            .font(.system(.title3, design: .rounded))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        if let example = card.example {
                            Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                }

                if translationVisible, card.example != nil { translationLine(card) }

                // Hearing the word or its sentence would give the answer away, so these wait for the reveal.
                if revealed {
                    HStack(spacing: 10) {
                        SpeakButton(
                            text: (app.profile.display.showsReadings ? card.entries.first?.reading : nil) ?? card.word.lemma,
                            languageCode: app.profile.whisperCode, showsTitle: true, shortcut: "w")
                        if card.example != nil {
                            Button { playSentence() } label: { KeyedLabel(title: "Play sentence", systemImage: "speaker.wave.2.fill", key: "R") }
                                .buttonStyle(.pill(.secondary, compact: true))
                                .keyboardShortcut("r", modifiers: [])
                                .help("Play this sentence from your video (R)")
                            Menu {
                                if canTranslate {
                                    Button(translationVisible ? "Hide translation" : "Show translation", action: toggleTranslation)
                                }
                                Button("Edit sentence…", action: editSentence)
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: PillIconStyle.width)
                            }
                            .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                            .help("Translate or fix this sentence")
                            .accessibilityLabel("More actions for this sentence")
                            .background {
                                // The menu's items have no keys of their own; these give T and E.
                                Group {
                                    Button("Edit sentence", action: editSentence).keyboardShortcut("e", modifiers: [])
                                    if canTranslate { Button("Translate sentence", action: toggleTranslation).keyboardShortcut("t", modifiers: []) }
                                }
                                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 560)
            .padding(.vertical, 30).padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .panel(padding: 0, radius: 28)
            .animation(Theme.easeOut(0.18), value: revealed)

            Spacer(minLength: 0)

            if revealed {
                HStack(spacing: 16) {
                    Button { Task { await answer(false) } } label: { KeyedLabel(title: "Missed it", systemImage: "xmark", key: "←") }
                        .buttonStyle(.pill(.secondary))
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { Task { await answer(true) } } label: { KeyedLabel(title: "Got it", systemImage: "checkmark", key: "→") }
                        .buttonStyle(.pill)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
            } else {
                Button {
                    if dictation(for: card) { checkDictation(); return }
                    revealed = true
                    // In a fill-in card the sentence is the question, so hearing it before the answer would give it away.
                    if !listening(for: card), mode == .onReveal || (mode == .onCardShown && cloze(for: card) != nil) { playSentence() }
                } label: {
                    KeyedLabel(title: "Show answer", key: dictation(for: card) ? nil : "Space")
                }
                .buttonStyle(.pill(dictation(for: card) ? .secondary : .primary))
                // Space is a letter while typing, so a typed card checks with Return instead.
                .keyboardShortcut(dictation(for: card) ? nil : KeyboardShortcut(.space, modifiers: []))
            }
            if !shortcutHints.isEmpty { ShortcutHints(items: shortcutHints) }
        }
        .padding(28)
    }

    /// The fill-in version of a card, when that is the chosen style and the word has a sentence to blank.
    /// "つき・がつ": every reading the word has, so a word read two ways is learned both ways.
    private func readings(of card: ReviewCard) -> String? {
        let all = card.entries.readings(of: card.word.lemma, first: card.entries.first?.reading)
        return all.isEmpty ? nil : all.joined(separator: "・")
    }

    private func cloze(for card: ReviewCard) -> ClozeCard? {
        style == .cloze ? ClozeCard.make(from: card, showsReading: app.profile.display.showsReadings) : nil
    }

    /// Whether this card is asked by ear: the chosen style, and a sentence to play.
    private func listening(for card: ReviewCard?) -> Bool {
        style == .listening && card?.example != nil
    }

    /// Only the sound of the sentence until the answer: the text, the word and its meaning follow.
    @ViewBuilder
    private func listenFace(_ card: ReviewCard) -> some View {
        if revealed {
            if let example = card.example {
                Text(highlighted(example)).font(.system(size: 26, design: .rounded)).multilineTextAlignment(.center)
            }
            answerBlock(card)
        } else {
            Image(systemName: "ear").font(.system(size: 44, weight: .regular)).foregroundStyle(Theme.ink).accessibilityHidden(true)
            Text("Listen").font(Theme.title(26))
            Text("What does the sentence say? Play it as often as you like, then show the answer.")
                .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { playSentence() } label: { KeyedLabel(title: "Play again", systemImage: "speaker.wave.2.fill", key: "R") }
                .buttonStyle(.pill(.secondary, compact: true))
                .keyboardShortcut("r", modifiers: [])
                .help("Play the sentence again (R)")
        }
    }

    /// The sentence with a blank (the question), filled in with its meaning once the answer is showing.
    @ViewBuilder
    private func clozeFace(_ cloze: ClozeCard, _ card: ReviewCard) -> some View {
        if revealed {
            Text(filled(cloze)).font(.system(size: 28, design: .rounded)).multilineTextAlignment(.center)
            answerBlock(card)
        } else {
            Text(cloze.prompt).font(.system(size: 28, design: .rounded)).multilineTextAlignment(.center)
            if !cloze.hint.isEmpty {
                Text(cloze.hint).font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            StatusPill(text: card.word.pos.title)
        }
    }

    /// The answer under a sentence: the word (a noun with its article), its reading and meaning, and where the line is from.
    private func answerBlock(_ card: ReviewCard) -> some View {
        VStack(spacing: 8) {
            lemmaText(card, font: Theme.title(22))
            if app.profile.display.showsReadings, let reading = readings(of: card) {
                Text(reading).font(Theme.title(18)).foregroundStyle(Theme.ink)
            }
            Text(card.entries.first?.gloss ?? "No dictionary entry")
                .font(.system(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
            if let example = card.example { Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint) }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    /// Whether this card is typed from hearing it: the chosen style, and a sentence short enough to hold in your head.
    private func dictation(for card: ReviewCard?) -> Bool {
        style == .dictation && card?.example.map(app.profile.suitsDictation) == true
    }

    /// Hear the sentence and type it; checked, it shows the sentence with what you missed marked.
    @ViewBuilder
    private func dictationFace(_ card: ReviewCard) -> some View {
        if revealed, let result = dictationResult {
            Text(dictationSummary(result)).font(Theme.title(20))
            Text(dictationDiff(result)).multilineTextAlignment(.center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dictationSpoken(result))
            answerBlock(card)
        } else {
            Image(systemName: "keyboard").font(.system(size: 44, weight: .regular)).foregroundStyle(Theme.ink).accessibilityHidden(true)
            Text("Type what you hear").font(Theme.title(26))
            Text("Play it as often as you like. Accents count; capitals and punctuation don't.")
                .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            TextField("What did you hear?", text: $typed, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .font(.system(size: 20, design: .rounded))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.soft))
                .focused($typingFocused)
                .onSubmit(checkDictation)
                .onAppear { DispatchQueue.main.async { typingFocused = true } }
            HStack(spacing: 10) {
                Button("Play again", systemImage: "speaker.wave.2.fill") { playSentence() }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Play the sentence again (⌘R)")
                Button("Check", action: checkDictation).buttonStyle(.pill(compact: true))
            }
        }
    }

    private func checkDictation() {
        guard let line = card?.example?.text else { return }
        dictationResult = DictationCheck.compare(typed: typed, line: line, profile: app.profile)
        revealed = true
    }

    private func dictationSummary(_ result: DictationCheck) -> String {
        if result.isExact { return String(localized: "All right") }
        return app.profile.dictationSeparator.isEmpty
            ? inflected("\(result.correct) of ^[\(result.total) character](inflect: true) right")
            : inflected("\(result.correct) of ^[\(result.total) word](inflect: true) right")
    }

    /// The sentence, with what was missed in bold and underlined and what was typed in error struck through. The marks
    /// never carry the meaning alone: the spoken version below names them.
    private func dictationDiff(_ result: DictationCheck) -> AttributedString {
        var text = AttributedString()
        for (index, piece) in result.pieces.enumerated() {
            var part = AttributedString(piece.text)
            part.font = .system(size: 26, weight: piece.kind == .missed ? .bold : .regular, design: .rounded)
            switch piece.kind {
            case .same: break
            case .missed: part.underlineStyle = .single
            case .extra: part.strikethroughStyle = .single; part.foregroundColor = Color(Theme.muted)
            }
            if index > 0 { text.append(AttributedString(app.profile.dictationSeparator)) }
            text.append(part)
        }
        return text
    }

    private func dictationSpoken(_ result: DictationCheck) -> String {
        let separator = app.profile.dictationSeparator
        let sentence = result.pieces.filter { $0.kind != .extra }.map(\.text).joined(separator: separator)
        let missed = result.pieces.filter { $0.kind == .missed }.map(\.text)
        let extra = result.pieces.filter { $0.kind == .extra }.map(\.text)
        var parts = [dictationSummary(result), sentence]
        if !missed.isEmpty { parts.append(String(localized: "Missed: \(listed(missed))")) }
        if !extra.isEmpty { parts.append(String(localized: "Typed in error: \(listed(extra))")) }
        return parts.joined(separator: ". ")
    }

    private func filled(_ cloze: ClozeCard) -> AttributedString {
        var text = AttributedString(cloze.before)
        var answer = AttributedString(cloze.answer)
        answer.font = .system(size: 28, weight: .semibold, design: .rounded)
        answer.foregroundColor = Color(Theme.ink)
        text.append(answer)
        text.append(AttributedString(cloze.after))
        return text
    }

    /// The keys that work right now: they change once the answer is showing.
    private var shortcutHints: [(key: String, action: String)] {
        guard revealed else {
            if dictation(for: card) { return [("Return", "Check"), ("⌘R", "Play again")] }
            return []   // Space and R are on the buttons
        }
        var hints: [(key: String, action: String)] = [("W", "Say word"), ("I", "Word page")]
        if card?.example != nil { hints.append(("E", "Edit sentence")) }
        if canTranslate, card?.example != nil { hints.append(("T", "Translation")) }
        return hints
    }

    private var translationMode: TranslationDisplay { env.translation.display }
    private var canTranslate: Bool { translationMode != .off && env.translation.translates(from: app.profile.whisperCode) }
    /// A listening card has just been heard and read, so what it meant is the natural next thing to see.
    private var translationByDefault: Bool { translationMode == .always || ((listening(for: card) || dictation(for: card)) && translationMode != .off) }
    private var translationVisible: Bool { revealed && canTranslate && (translationChoice ?? translationByDefault) }

    private func toggleTranslation() {
        guard canTranslate, card?.example != nil, revealed else { return }
        translationChoice = !translationVisible
    }

    /// Only after the answer: the translation of the sentence would give the word's meaning away.
    @ViewBuilder
    private func translationLine(_ card: ReviewCard) -> some View {
        if let example = card.example, let text = translations?.texts[example.id] {
            Text(text).font(.system(.callout, design: .rounded)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).textSelection(.enabled)
                .accessibilityLabel("Translation: \(text)")
        } else if let problem = translations?.problem {
            Text(problem).font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        } else {
            Text("Translating…").font(Theme.small).foregroundStyle(Theme.faint)
        }
    }

    /// Fetches the sentence's translation once it is asked for, from the video it belongs to.
    private func loadTranslation() async {
        guard translationVisible, let example = card?.example else { return }
        if translationsVideo != example.videoID || translations == nil {
            guard let service = env.translationService(for: app.profile) else { return }
            let model = LineTranslations(service: service, videoID: example.videoID, source: app.profile.whisperCode, target: service.target)
            translations = model
            translationsVideo = example.videoID
            await model.load()
        }
        translations?.need(Subtitle(id: example.id, videoId: example.videoID, idx: 0, startTime: example.startTime,
                                    endTime: example.endTime, text: example.text))
    }

    private func editSentence() {
        guard let example = card?.example else { return }
        audio?.stop()
        Task {
            let videos = (try? await env.database.libraryVideos()) ?? []
            editingDuration = videos.first { $0.id == example.videoID }?.video.duration ?? example.endTime + 30
            editingExample = example
        }
    }

    private func playSentence() {
        guard let example = card?.example, let audio else { return }
        Task { await audio.play(example) }
    }

    /// The sentence with the word as it appears in it picked out.
    private func highlighted(_ example: ExampleLine) -> AttributedString {
        var text = AttributedString(example.text)
        if let range = text.range(of: example.surface, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].font = .system(.body, design: .rounded, weight: .medium)
            text[range].foregroundColor = Color(Theme.ink)
        }
        return text
    }

    /// Loads the page's overview. After a session it is kept beneath the summary, and refreshed.
    private func loadOverview(keepingSummary: Bool = false) async {
        if !keepingSummary { session = nil; card = nil; summary = nil; extra = nil }
        error = nil
        do {
            overview = try await env.database.reviewOverview(language: app.languageCode)
            stats = try await env.database.learningStats(language: app.languageCode)
        } catch { self.error = error.localizedDescription }
    }

    private func endSession() {
        audio?.stop()
        session = nil; card = nil; summary = nil; revealed = false; showsWord = false; wordNow = nil; translationChoice = nil; typed = ""; dictationResult = nil; extra = nil
        Task { await loadOverview() }
    }

    /// The card type, chosen where a session is started and remembered for the language.
    private var styleChoice: Binding<ReviewStyle> {
        Binding(
            get: { style },
            set: { style = $0; env.reviewStyle.setStyle($0, for: app.profile) })
    }

    private func startSession(extra: ExtraStudy? = nil) { Task { await begin(extra: extra) } }

    private func begin(extra chosen: ExtraStudy? = nil) async {
        session = nil; card = nil; summary = nil; error = nil; revealed = false
        audio?.stop()
        audio = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        mode = env.reviewAudio.mode(for: app.profile)
        style = env.reviewStyle.style(for: app.profile)
        do {
            // Typing needs a short line, so a word with one gets that one and not a long one.
            let profile = app.profile
            var short: (@Sendable (ExampleLine) -> Bool)?
            if style == .dictation { short = { profile.suitsDictation($0) } }
            let new: ReviewSession
            switch chosen {
            case nil: new = try await ReviewSession(database: env.database, language: app.languageCode, preferring: short)
            case .known: new = try await ReviewSession(checkingKnown: env.database, language: app.languageCode)
            case .ahead: new = try await ReviewSession(practising: .ahead, database: env.database, language: app.languageCode, preferring: short)
            case .finished: new = try await ReviewSession(practising: .finished, database: env.database, language: app.languageCode, preferring: short)
            }
            extra = chosen
            session = new
            total = await new.remaining
            remaining = total   // set together with the total, or the bar shows full for a moment
            await advance(new)
        } catch { self.error = error.localizedDescription }
    }

    private func answer(_ correct: Bool) async {
        guard let session else { return }
        audio?.stop()
        do {
            try await session.answer(correct: correct)
            await app.refreshDue()
            await advance(session)
        } catch { self.error = error.localizedDescription }
    }

    private func advance(_ session: ReviewSession) async {
        revealed = false; showsWord = false; wordNow = nil; translationChoice = nil; typed = ""; dictationResult = nil
        do {
            let next = try await session.currentCard()
            // Update the counts before the card, so the bar never shows a card with a stale count.
            remaining = await session.remaining
            total = max(total, remaining)   // a missed word re-enters the queue, so the total can grow
            card = next
            if let next {
                if listening(for: next) || dictation(for: next) { playSentence() }   // the sentence is the question: it plays whatever the audio setting
                else if mode == .onCardShown, cloze(for: next) == nil { playSentence() }
            }
            if card == nil, await session.answered > 0 {
                summary = (await session.answered, await session.correctFirstTry)
                returned = await session.returnedToLearning
                if await session.isKnownCheck { app.dataChanged() }   // coverage and the word lists have changed
                await loadOverview(keepingSummary: true)
            }
        } catch { self.error = error.localizedDescription }
    }
}
