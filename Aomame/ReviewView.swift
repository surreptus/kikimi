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
    @State private var checking = false
    @State private var returned = 0

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Review failed", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let card {
                cardView(card)
            } else if let summary {
                VStack(spacing: 0) {
                    finished(summary).padding(.top, 28)
                    if let overview, !overview.isEmpty { ReviewOverviewView(overview: overview, stats: stats, start: { startSession() }, checkKnown: { startSession(checkingKnown: true) }) }
                }
            } else if let overview {
                if overview.isEmpty {
                    EmptyState(title: "Nothing to review yet", message: "Start learning words from the Words tab, then come back.")
                } else {
                    ReviewOverviewView(overview: overview, stats: stats, start: { startSession() }, checkKnown: { startSession(checkingKnown: true) })
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: mode) { _, new in env.reviewAudio.setMode(new, for: app.profile) }
        .task(id: app.languageCode) { await loadOverview() }
        .task(id: app.dataVersion) { if card == nil { await loadOverview(keepingSummary: true) } }
        .onDisappear { audio?.stop() }
    }

    private func finished(_ summary: (answered: Int, correct: Int)) -> some View {
        VStack(spacing: 12) {
            Text(checking ? "Check finished" : "All done for now").font(Theme.title(30))
            Text(checking
                 ? "You knew \(summary.correct) of \(summary.answered) of the words you marked known."
                 : "\(summary.correct) of \(summary.answered) answers right the first time.")
                .font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted)
            if checking, returned > 0 {
                Text(inflected("^[\(returned) word](inflect: true) went back to your reviews, so each video's coverage no longer counts it as known."))
                    .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }
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
                } else {
                Text(card.word.lemma).font(.system(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.title)

                if revealed {
                    VStack(spacing: 10) {
                        if app.profile.display.showsReadings, let reading = card.entries.first?.reading {
                            Text(reading).font(Theme.title(22)).foregroundStyle(Theme.ink)
                        }
                        Text(card.entries.first?.gloss ?? "No dictionary entry")
                            .font(.system(.title3, design: .rounded))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        if let example = card.example {
                            Divider().padding(.horizontal, 60).padding(.vertical, 4)
                            Text(highlighted(example)).font(.system(.body, design: .rounded)).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                            Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                }

                // Hearing the word or its sentence would give the answer away, so these wait for the reveal.
                if revealed {
                    HStack(spacing: 10) {
                        SpeakButton(
                            text: (app.profile.display.showsReadings ? card.entries.first?.reading : nil) ?? card.word.lemma,
                            languageCode: app.profile.whisperCode, showsTitle: true, shortcut: "w")
                        if card.example != nil {
                            Button("Play sentence", systemImage: "speaker.wave.2.fill") { playSentence() }
                                .buttonStyle(.pill(.secondary, compact: true))
                                .keyboardShortcut("r", modifiers: [])
                                .help("Play this sentence from your video (R)")
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
            .animation(.easeOut(duration: 0.18), value: revealed)

            Spacer(minLength: 0)

            if revealed {
                HStack(spacing: 16) {
                    Button { Task { await answer(false) } } label: { Label("Missed it", systemImage: "xmark") }
                        .buttonStyle(.pill(.secondary))
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { Task { await answer(true) } } label: { Label("Got it", systemImage: "checkmark") }
                        .buttonStyle(.pill)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
            } else {
                Button("Show answer") {
                    revealed = true
                    // In a fill-in card the sentence is the question, so hearing it before the answer would give it away.
                    if !listening(for: card), mode == .onReveal || (mode == .onCardShown && cloze(for: card) != nil) { playSentence() }
                }
                .buttonStyle(.pill(.primary))
                .keyboardShortcut(.space, modifiers: [])
            }
            ShortcutHints(items: shortcutHints)
        }
        .padding(28)
    }

    /// The fill-in version of a card, when that is the chosen style and the word has a sentence to blank.
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
            VStack(spacing: 8) {
                Text(card.word.lemma).font(Theme.title(22))
                if app.profile.display.showsReadings, let reading = card.entries.first?.reading {
                    Text(reading).font(Theme.title(18)).foregroundStyle(Theme.ink)
                }
                Text(card.entries.first?.gloss ?? "No dictionary entry")
                    .font(.system(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
                if let example = card.example { Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint) }
            }
            .padding(.top, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            Image(systemName: "ear").font(.system(size: 44, weight: .regular)).foregroundStyle(Theme.ink).accessibilityHidden(true)
            Text("Listen").font(Theme.title(26))
            Text("What does the sentence say? Play it as often as you like, then show the answer.")
                .font(Theme.small).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Play again", systemImage: "speaker.wave.2.fill") { playSentence() }
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
            VStack(spacing: 8) {
                Text(card.word.lemma).font(Theme.title(22))
                if app.profile.display.showsReadings, let reading = card.entries.first?.reading {
                    Text(reading).font(Theme.title(18)).foregroundStyle(Theme.ink)
                }
                Text(card.entries.first?.gloss ?? "No dictionary entry")
                    .font(.system(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
                if let example = card.example {
                    Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint)
                }
            }
            .padding(.top, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            Text(cloze.prompt).font(.system(size: 28, design: .rounded)).multilineTextAlignment(.center)
            if !cloze.hint.isEmpty {
                Text(cloze.hint).font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            StatusPill(text: card.word.pos.title)
        }
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
        guard revealed else { return listening(for: card) ? [("Space", "Show answer"), ("R", "Play again")] : [("Space", "Show answer")] }
        var hints: [(key: String, action: String)] = [("←", "Missed it"), ("→", "Got it"), ("W", "Say word")]
        if card?.example != nil { hints.append(("R", "Play sentence")) }
        return hints
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
        if !keepingSummary { session = nil; card = nil; summary = nil; checking = false }
        error = nil
        do {
            overview = try await env.database.reviewOverview(language: app.languageCode)
            stats = try await env.database.learningStats(language: app.languageCode)
        } catch { self.error = error.localizedDescription }
    }

    private func endSession() {
        audio?.stop()
        session = nil; card = nil; summary = nil; revealed = false; checking = false
        Task { await loadOverview() }
    }

    private func startSession(checkingKnown: Bool = false) { Task { await begin(checkingKnown: checkingKnown) } }

    private func begin(checkingKnown: Bool = false) async {
        session = nil; card = nil; summary = nil; error = nil; revealed = false
        audio?.stop()
        audio = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        mode = env.reviewAudio.mode(for: app.profile)
        style = env.reviewStyle.style(for: app.profile)
        do {
            let new = checkingKnown
                ? try await ReviewSession(checkingKnown: env.database, language: app.languageCode)
                : try await ReviewSession(database: env.database, language: app.languageCode)
            checking = checkingKnown
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
        revealed = false
        do {
            let next = try await session.currentCard()
            // Update the counts before the card, so the bar never shows a card with a stale count.
            remaining = await session.remaining
            total = max(total, remaining)   // a missed word re-enters the queue, so the total can grow
            card = next
            if let next {
                if listening(for: next) { playSentence() }   // the sentence is the question: it plays whatever the audio setting
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
