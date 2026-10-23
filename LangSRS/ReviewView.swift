import LangCore
import SwiftUI

struct ReviewView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var session: ReviewSession?
    @State private var card: ReviewCard?
    @State private var revealed = false
    @State private var remaining = 0
    @State private var total = 0
    @State private var summary: (answered: Int, correct: Int)?
    @State private var error: String?
    @State private var audio: SentenceAudioPlayer?
    @State private var mode: SentenceAudioMode = .onReveal

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Review failed", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let card {
                cardView(card)
            } else if let summary {
                finished(summary)
            } else if session != nil {
                ContentUnavailableView("Nothing due", systemImage: "tray",
                    description: Text("Start learning words from the Words tab, or come back later."))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Review")
        .onChange(of: mode) { _, new in env.reviewAudio.setMode(new, for: app.profile) }
        .task(id: app.languageCode) { await begin() }
        .onDisappear { audio?.stop() }
    }

    private func finished(_ summary: (answered: Int, correct: Int)) -> some View {
        VStack(spacing: 18) {
            Blob()
            Text("All done for now").font(Theme.title(30))
            Text("\(summary.correct) of \(summary.answered) answers right the first time.")
                .font(.system(.title3, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }

    private func cardView(_ card: ReviewCard) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
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
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                .help("When to play the sentence audio")
            }
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text(card.word.lemma).font(.system(size: 58, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                StatusPill(text: card.word.pos.rawValue)

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
                            Text(example.videoTitle).font(.caption2).foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if card.example != nil {
                    Button("Play sentence", systemImage: "speaker.wave.2.fill") { playSentence() }
                        .buttonStyle(.pill(.secondary, compact: true))
                        .keyboardShortcut("r", modifiers: [])
                        .help("Play this sentence from your video (R)")
                        .padding(.top, 6)
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
                    if mode == .onReveal { playSentence() }
                }
                .buttonStyle(.pill(.primary))
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding(28)
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

    private func begin() async {
        session = nil; card = nil; summary = nil; error = nil; revealed = false
        audio?.stop()
        audio = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        mode = env.reviewAudio.mode(for: app.profile)
        do {
            let new = try await ReviewSession(database: env.database, language: app.languageCode)
            session = new
            total = await new.remaining
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
            card = try await session.currentCard()
            remaining = await session.remaining
            total = max(total, remaining)   // a missed word re-enters the queue, so the total can grow
            if mode == .onCardShown { playSentence() }
            if card == nil, await session.answered > 0 {
                summary = (await session.answered, await session.correctFirstTry)
            }
        } catch { self.error = error.localizedDescription }
    }
}
