import LangCore
import SwiftUI

extension ExampleLine {
    /// The sentence with the word as it appears in it picked out.
    var highlighted: AttributedString {
        var styled = AttributedString(text)
        if let range = styled.range(of: surface, options: [.caseInsensitive, .diacriticInsensitive]) {
            styled[range].inlinePresentationIntent = .stronglyEmphasized   // keeps the line's own size
            styled[range].foregroundColor = Color(Theme.highlight)
        }
        return styled
    }
}

/// Teaching a few new words, one at a time, each in a sentence from your videos with its meaning showing. Next teaches
/// the word; Already know it marks it known. When the batch is done the page quizzes it at once, so each word is asked
/// while it is fresh. The words are started only when that quiz is finished, so leaving early starts none of them.
struct LessonView: View {
    let env: LangEnvironment
    let wordIDs: [Int64]
    /// The words that were taught, and whether to quiz them. Leaving early does not quiz, and starts nothing.
    let finish: (_ taught: [Int64], _ quiz: Bool) -> Void
    @Environment(AppState.self) private var app
    @State private var index = 0
    @State private var card: ReviewCard?
    @State private var taught: [Int64] = []
    @State private var known = 0
    @State private var audio: SentenceAudioPlayer?
    @State private var error: String?
    /// Leaving asks first: Esc is easy to press by mistake, and the words taught so far are not started.
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Button("End lesson", systemImage: "xmark") { confirmingEnd = true }
                    .labelStyle(.pillIcon).buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Back to the Learn page (Esc). Words you were taught but not yet quizzed on are not started.")
                ProgressView(value: Double(index), total: Double(max(1, wordIDs.count)))
                    .progressViewStyle(.thin)
                Text("\(max(0, wordIDs.count - index)) left").font(Theme.sized(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 28).padding(.top, 20)

            Spacer(minLength: 0)
            if let error {
                FailureView(title: "Something went wrong", detail: error)
            } else if let card {
                face(card)
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: index) { await load() }
        .onDisappear { audio?.stop() }
        .alert("Leave this lesson?", isPresented: $confirmingEnd) {
            Button("Keep Learning", role: .cancel) {}.keyboardShortcut(.defaultAction)
            Button("Leave Lesson", role: .destructive) { Task { await end() } }
        } message: {
            Text("Words you were taught but not yet quizzed on are not started. Words you marked known stay known.")
        }
    }

    private func face(_ card: ReviewCard) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Text(lemma(card)).font(Theme.sized(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.title)
                if app.profile.display.showsReadings, case let all = card.entries.readings(of: card.word.lemma, first: card.entries.first?.reading), !all.isEmpty {
                    Text(all.joined(separator: "・")).font(Theme.title(22))
                }
                Text(card.entries.first?.gloss ?? String(localized: "No dictionary entry"))
                    .font(Theme.styled(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
                WordKanji(env: env, lemma: card.word.lemma, language: card.word.language)
                if let example = card.example {
                    Text(example.highlighted).font(Theme.styled(.body, design: .rounded)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center).padding(.top, 6)
                    Text(example.videoTitle).font(Theme.small).foregroundStyle(Theme.faint)
                    Button { play() } label: { KeyedLabel(title: "Play sentence", systemImage: "speaker.wave.2.fill", key: "R") }
                        .buttonStyle(.pill(.secondary, compact: true))
                        .keyboardShortcut("r", modifiers: [])
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 560)
            .padding(.vertical, 30).padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .panel(padding: 0, radius: 28)

            HStack(spacing: 16) {
                Button { Task { await answer(teach: nil) } } label: { KeyedLabel(title: "Ignore", systemImage: "eye.slash", key: "X") }
                    .buttonStyle(.pill(.quiet))
                    .keyboardShortcut("x", modifiers: [])
                    .help("Not a word worth learning, such as a name or a mistake. It is set aside and left out of lessons.")
                Button { Task { await answer(teach: false) } } label: { KeyedLabel(title: "Already know it", systemImage: "checkmark", key: "K") }
                    .buttonStyle(.pill(.secondary))
                    .keyboardShortcut("k", modifiers: [])
                Button { Task { await answer(teach: true) } } label: { KeyedLabel(title: "Next", systemImage: "arrow.right", key: "Return") }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
            }
            Text("You will be asked these words as soon as you have seen them all.")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .padding(28)
    }

    private func lemma(_ card: ReviewCard) -> String {
        guard card.word.pos == .noun else { return card.word.lemma }
        return card.entries.nounPhrase(using: app.profile) ?? card.word.lemma
    }

    private func load() async {
        guard index < wordIDs.count else { card = nil; return }
        do {
            card = try await env.database.lessonCard(wordID: wordIDs[index], language: app.languageCode)
            if card == nil { index += 1; return }
            if audio == nil { audio = SentenceAudioPlayer(libraryRoot: env.libraryURL) }
            if env.reviewAudio.mode(for: app.profile) != .off { play() }
        } catch { self.error = error.localizedDescription }
    }

    private func play() {
        guard let example = card?.example, let audio else { return }
        Task { await audio.play(example) }
    }

    /// `true` teaches the word, `false` marks it known, nil sets it aside.
    private func answer(teach: Bool?) async {
        guard let id = card?.word.id else { return }
        audio?.stop()
        do {
            switch teach {
            case true?: taught.append(id)
            case false?: try await env.database.markKnown(wordID: id); known += 1
            case nil: try await env.database.markIgnored(wordIDs: [id]); known += 1   // saved now, so the Words page is refreshed
            }
            card = nil
            index += 1
            if index >= wordIDs.count { await end(quiz: true) }
        } catch { self.error = error.localizedDescription }
    }

    /// Hands the taught words on to be quizzed, or, when leaving early, hands on nothing. Words marked known are already
    /// saved, since that was a decision of its own.
    private func end(quiz: Bool = false) async {
        audio?.stop()
        if known > 0 { app.dataChanged() }
        finish(quiz ? taught : [], quiz)
    }
}
