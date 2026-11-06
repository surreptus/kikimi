import LangCore
import SwiftUI

struct ReviewView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var overview: ReviewOverview?
    @State private var lessons: DailyLessons?
    /// The words of the lesson being taught now.
    @State private var teaching: [Int64]?
    /// The rest of today's lessons, in the groups they are taught.
    @State private var lessonQueue: [[Int64]] = []
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
    @State private var voice = VoiceRecorder()
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
                FailureView(title: "Something went wrong", detail: error)
            } else if let teaching {
                LessonView(env: env, wordIDs: teaching, finish: lessonFinished)
            } else if let card {
                cardWithWord(card)
            } else if let summary {
                VStack(spacing: 0) {
                    finished(summary).padding(.top, 28)
                    if let overview, !overview.isEmpty, extra != .lesson { ReviewOverviewView(overview: overview, lessons: lessons, stats: stats, style: styleChoice, startLessons: startLessons, start: { startSession() }, practise: { startSession(extra: $0) }) }
                }
            } else if let overview {
                if overview.isEmpty, lessons?.wordIDs.isEmpty ?? true {
                    EmptyState(title: "Nothing to review yet", message: "Choose words to learn on the Words page, then come back.",
                               actionTitle: "Go to Words", action: { app.select(.words) })
                } else {
                    ReviewOverviewView(overview: overview, lessons: lessons, stats: stats, style: styleChoice, startLessons: startLessons, start: { startSession() }, practise: { startSession(extra: $0) })
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
        .task(id: app.pendingLesson) { takePendingLesson() }
        .onDisappear { audio?.stop(); voice.discard() }
        // Having said it, the answer is what you want next.
        .onChange(of: voice.state) { _, state in if state == .recorded, shadowing(for: card) { revealed = true } }
    }

    private func finished(_ summary: (answered: Int, correct: Int)) -> some View {
        VStack(spacing: 12) {
            Text(extra == nil ? "All done for now" : extra == .lesson ? "Lesson done" : "Practice done").font(Theme.title(30))
            Text(summaryText(summary))
                .font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted)
            if extra == .lesson {
                HStack(spacing: 12) {
                    if !lessonQueue.isEmpty {
                        Button("Next \(min(DailyLessons.batchSize, lessonQueue[0].count)) words") { teachNext() }
                            .buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
                    }
                    Button("Back to Learn") { endSession() }
                        .buttonStyle(.pill(lessonQueue.isEmpty ? .primary : .secondary, compact: true))
                        .keyboardShortcut(lessonQueue.isEmpty ? .defaultAction : nil)
                }
                .padding(.top, 8)
            }
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
        case .lesson: String(localized: "\(summary.correct) of \(summary.answered) right the first time. They come back for review in a few hours.")
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
                    editingExample = nil
                    app.dataChanged()
                    Task {
                        // The fix may have taken the word out of the sentence (it was misread as another word): the card
                        // can't be asked any more, so it is skipped and the word is asked another time.
                        let stillThere = (try? await env.database.wordOccurs(wordID: card.id, inSubtitle: example.id)) ?? true
                        if stillThere {
                            self.card = card.showing(example.edited(text: saved.text, start: saved.startTime, end: saved.endTime))
                        } else {
                            await skipCard(word: card.word.lemma)
                        }
                    }
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
                } else if shadowing(for: card) {
                    shadowFace(card)
                } else {
                lemmaText(card, font: .system(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.title)

                // The word as it was said in your video: the context is part of the question, the translation is not.
                if let example = card.example {
                    Text(example.highlighted).font(.system(.body, design: .rounded)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                if revealed {
                    VStack(spacing: 10) {
                        if app.profile.display.showsReadings, let reading = readings(of: card) {
                            Text(reading).font(Theme.title(22)).foregroundStyle(Theme.ink)
                        }
                        Text(card.entries.first?.gloss ?? "No dictionary entry")
                            .font(.system(.title3, design: .rounded)).lineSpacing(4)
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
                // A shadow card has its own buttons for hearing the sentence.
                if revealed, !shadowing(for: card) {
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
                Text(example.highlighted).font(.system(size: 26, design: .rounded)).multilineTextAlignment(.center)
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

    /// Whether this card is said aloud: the chosen style, and a sentence short enough to repeat.
    private func shadowing(for card: ReviewCard?) -> Bool {
        style == .shadowing && card?.example.map(app.profile.suitsDictation) == true
    }

    /// The meaning is the question; the sentence itself would give it away, so it waits for the answer. Hear it, say it
    /// after, then play yourself beside the original. Nothing is judged: you compare by ear, and answer Got it or Missed
    /// it yourself. The recording lives only while the card does, and finishing it shows the answer.
    @ViewBuilder
    private func shadowFace(_ card: ReviewCard) -> some View {
        if let example = card.example {
            Image(systemName: "mic").font(.system(size: 44, weight: .regular)).foregroundStyle(Theme.ink).accessibilityHidden(true)
            if revealed {
                Text(example.highlighted).font(.system(size: 26, design: .rounded)).multilineTextAlignment(.center)
                lemmaText(card, font: Theme.title(20))
                if app.profile.display.showsReadings, let reading = readings(of: card) {
                    Text(reading).font(Theme.title(16)).foregroundStyle(Theme.ink)
                }
            } else {
                Text("Say it aloud").font(Theme.title(26))
            }
            Text(card.entries.first.flatMap { ClozeCard.shortGloss($0.gloss) } ?? card.entries.first?.gloss ?? "No dictionary entry")
                .font(.system(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
            HStack(spacing: 10) {
                Button { playSentence() } label: { KeyedLabel(title: "Hear it", systemImage: "speaker.wave.2.fill", key: "R") }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut("r", modifiers: [])
                    .help("Play the sentence from your video (R)")
                Button {
                    if voice.state == .recording { voice.stop() }
                    else { audio?.stop(); Task { await voice.start(maxSeconds: min(20, (example.endTime - example.startTime) * 2 + 3)) } }
                } label: {
                    KeyedLabel(title: voice.state == .recording ? "Stop" : "Record", systemImage: voice.state == .recording ? "stop.fill" : "mic.fill", key: "M")
                }
                .buttonStyle(.pill(voice.state == .recording ? .primary : .secondary, compact: true))
                .keyboardShortcut("m", modifiers: [])
                .help("Record yourself saying the sentence (M). The recording is deleted when the card ends.")
                if voice.state == .recorded {
                    Button { audio?.stop(); voice.togglePlayback() } label: {
                        KeyedLabel(title: voice.isPlaying ? "Stop" : "Hear yourself", systemImage: voice.isPlaying ? "stop.fill" : "waveform", key: "Y")
                    }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut("y", modifiers: [])
                }
            }
            switch voice.state {
            case .recording:
                Text("Recording… say the sentence, then press Stop.").font(Theme.small).foregroundStyle(Theme.muted)
            case .denied:
                VStack(spacing: 6) {
                    Text("Kikimi can't use the microphone. You can allow it in System Settings > Privacy & Security > Microphone.")
                        .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    Button("Open Microphone Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.pill(.secondary, compact: true))
                }
            case .failed:
                Text("Couldn't record. Check your microphone and try again.").font(Theme.small).foregroundStyle(Theme.muted)
            default:
                if !revealed {
                    Text("Listen, then repeat the sentence aloud.")
                        .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
            }
        }
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
                .onChange(of: typingFocused) { _, focused in
                    guard focused else { KeyboardSwitch.restore(); return }
                    // The field editor takes over a moment after focus, so the keyboard is chosen just after.
                    let keywords = app.profile.keyboardKeywords
                    Task { try? await Task.sleep(for: .milliseconds(100)); KeyboardSwitch.use(keywords: keywords) }
                }
                .onDisappear { KeyboardSwitch.restore() }
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
        answer.foregroundColor = Color(Theme.highlight)
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

    /// Moves past a card that no longer fits its edited sentence, without answering it.
    private func skipCard(word: String) async {
        guard let session else { return }
        _ = try? await session.skipCurrent()
        app.showToast(String(localized: "“\(word)” is no longer in that sentence, so this card was skipped."))
        await advance(session)
        if card == nil, summary == nil { await loadOverview(keepingSummary: true) }
    }

    private func playSentence() {
        guard let example = card?.example, let audio else { return }
        Task { await audio.play(example) }
    }


    /// Loads the page's overview. After a session it is kept beneath the summary, and refreshed.
    private func loadOverview(keepingSummary: Bool = false) async {
        if !keepingSummary { session = nil; card = nil; summary = nil; extra = nil }
        error = nil
        do {
            overview = try await env.database.reviewOverview(language: app.languageCode)
            lessons = try await env.database.dailyLessons(
                language: app.languageCode, contentPOS: app.profile.contentPOS, perDay: env.dailyLessons.perDay(for: app.profile))
            stats = try await env.database.learningStats(language: app.languageCode)
        } catch { self.error = error.localizedDescription }
    }

    private func startLessons() {
        lessonQueue = lessons?.batches ?? []
        teachNext()
    }

    /// Words sent here by another page, taught like the day's lessons. Only the ones still new are taught: a word you have
    /// ignored, marked known or started since the list was made is left out.
    private func takePendingLesson() {
        let wanted = app.pendingLesson
        guard !wanted.isEmpty else { return }
        app.pendingLesson = []
        // Its own task: clearing the list above restarts the task that watches it, which would cancel this work part-way
        // through, and a cancelled database read throws.
        Task {
            do {
                let ids = try await env.database.stillNew(wanted)
                guard !ids.isEmpty else {
                    app.showToast(String(localized: "Those words are already known, set aside or in your reviews."))
                    return
                }
                lessonQueue = stride(from: 0, to: ids.count, by: DailyLessons.batchSize).map { Array(ids[$0..<min($0 + DailyLessons.batchSize, ids.count)]) }
                teachNext()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func teachNext() {
        guard !lessonQueue.isEmpty else { teaching = nil; Task { await loadOverview() }; return }
        teaching = lessonQueue.removeFirst()
        summary = nil; extra = nil
    }

    /// A batch has been taught: quiz it at once, or, if it was left early, go back with nothing more to do.
    private func lessonFinished(_ started: [Int64], quiz: Bool) {
        teaching = nil
        guard quiz else { lessonQueue = []; Task { await loadOverview() }; return }
        if started.isEmpty { teachNext() } else { Task { await begin(extra: .lesson, lessonWords: started) } }
    }

    private func endSession() {
        lessonQueue = []
        style = env.reviewStyle.style(for: app.profile)
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

    private func begin(extra chosen: ExtraStudy? = nil, lessonWords: [Int64] = []) async {
        session = nil; card = nil; summary = nil; error = nil; revealed = false
        audio?.stop()
        audio = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        mode = env.reviewAudio.mode(for: app.profile)
        // A lesson's quiz is always word and meaning, whatever card type is chosen for reviews (which is left as it was).
        style = chosen == .lesson ? .meaning : env.reviewStyle.style(for: app.profile)
        do {
            // Typing needs a short line, so a word with one gets that one and not a long one.
            let profile = app.profile
            var short: (@Sendable (ExampleLine) -> Bool)?
            if style == .dictation || style == .shadowing { short = { profile.suitsDictation($0) } }
            let new: ReviewSession
            switch chosen {
            case nil: new = try await ReviewSession(database: env.database, language: app.languageCode, preferring: short)
            case .known: new = try await ReviewSession(checkingKnown: env.database, language: app.languageCode, preferring: short)
            case .lesson: new = ReviewSession(lessonQuiz: lessonWords, database: env.database, language: app.languageCode, preferring: short)
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
        voice.discard()   // the recording was for the card that has just been answered
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
                if await session.isKnownCheck || extra == .lesson { app.dataChanged() }   // the lists and coverage have changed
                await loadOverview(keepingSummary: true)
            }
        } catch { self.error = error.localizedDescription }
    }
}
