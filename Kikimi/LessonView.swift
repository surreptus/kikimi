import LangCore
import SwiftUI

extension ExampleLine {
    /// The sentence with the word as it appears in it picked out.
    var highlighted: AttributedString {
        var styled = AttributedString(text)
        if let range = styled.range(of: surface, options: [.caseInsensitive, .diacriticInsensitive]) {
            styled[range].font = .system(.body, design: .rounded, weight: .medium)
            styled[range].foregroundColor = Color(Theme.ink)
        }
        return styled
    }
}

/// A lesson: the day's new words one at a time, each in a sentence from your videos, with its meaning showing. Learn
/// puts the word into your reviews; Known says you already know it. Nothing is added without a press.
struct LessonView: View {
    let env: LangEnvironment
    let wordIDs: [Int64]
    let finish: () -> Void
    @Environment(AppState.self) private var app
    @State private var index = 0
    @State private var card: ReviewCard?
    @State private var learned = 0
    @State private var known = 0
    @State private var audio: SentenceAudioPlayer?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Button("End lesson", systemImage: "xmark") { end() }
                    .labelStyle(.pillIcon).buttonStyle(.pill(.secondary, compact: true))
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Back to the Learn page (Esc). Words you have already answered are kept.")
                ProgressView(value: Double(index), total: Double(max(1, wordIDs.count)))
                    .progressViewStyle(.thin)
                Text("\(max(0, wordIDs.count - index)) left").font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 28).padding(.top, 20)

            Spacer(minLength: 0)
            if let error {
                Text(error).foregroundStyle(Theme.muted)
            } else if let card {
                face(card)
            } else if index >= wordIDs.count {
                done
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: index) { await load() }
        .onDisappear { audio?.stop() }
    }

    private func face(_ card: ReviewCard) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Text(lemma(card)).font(.system(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.title)
                if app.profile.display.showsReadings, let reading = card.entries.readings(of: card.word.lemma, first: card.entries.first?.reading).first {
                    Text(reading).font(Theme.title(22))
                }
                Text(card.entries.first?.gloss ?? String(localized: "No dictionary entry"))
                    .font(.system(.title3, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
                if let example = card.example {
                    Text(example.highlighted).font(.system(.body, design: .rounded)).foregroundStyle(Theme.muted)
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
                Button { Task { await answer(learn: false) } } label: { KeyedLabel(title: "Already know it", systemImage: "checkmark", key: "K") }
                    .buttonStyle(.pill(.secondary))
                    .keyboardShortcut("k", modifiers: [])
                Button { Task { await answer(learn: true) } } label: { KeyedLabel(title: "Learn", systemImage: "plus", key: "Return") }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Learn adds it to your reviews. Already know it marks it known.")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .padding(28)
    }

    private var done: some View {
        VStack(spacing: 12) {
            Text("Lesson done").font(Theme.title(30))
            Text(summary).font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Back to Learn") { end() }.buttonStyle(.pill).keyboardShortcut(.defaultAction).padding(.top, 8)
        }
    }

    private var summary: String {
        learned == 0
            ? String(localized: "No words added to your reviews.")
            : inflected("^[\(learned) word](inflect: true) added to your reviews, first one back in a few hours.")
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

    private func answer(learn: Bool) async {
        guard let id = card?.word.id else { return }
        audio?.stop()
        do {
            if learn { try await env.database.startLearning(wordID: id); learned += 1 }
            else { try await env.database.markKnown(wordID: id); known += 1 }
            card = nil
            index += 1
            await app.refreshDue()
        } catch { self.error = error.localizedDescription }
    }

    private func end() {
        audio?.stop()
        if learned + known > 0 { app.dataChanged() }
        finish()
    }
}
