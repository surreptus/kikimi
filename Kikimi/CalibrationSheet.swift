import LangCore
import SwiftUI

/// "I know these words" for one video: its most-seen new words in batches of twenty, where you tick the ones you know. More
/// words are offered only while at least half of a batch are known. Marking is one button that says how many words it marks,
/// and Undo follows it. The rules (the batches, when to stop, which words end up known) are in `Calibration`.
struct CalibrationSheet: View {
    let env: LangEnvironment
    let video: Video
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    private enum Step { case loading, asking, nothing }
    @State private var step = Step.loading
    @State private var batches: [[CalibrationWord]] = []
    @State private var index = 0
    @State private var ticked: Set<Int64> = []
    @State private var glosses: [Int64: String] = [:]
    @State private var error: Problem?

    private var batch: [CalibrationWord] { batches.indices.contains(index) ? batches[index] : [] }
    /// Whether another batch can be offered: there is one, and at least half of this one is known.
    private var canContinue: Bool { index < batches.count - 1 && !Calibration.endsAfter(batch, known: ticked) }
    private var toMark: [Int64] { Calibration.known(shown: Array(batches.prefix(index + 1)), ticked: ticked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            case .nothing: nothing
            case .asking: asking
            }
            if let error { ProblemView(problem: error) }
        }
        .padding(24)
        .frame(width: 560)
        .frame(maxHeight: 600)
        .background(Theme.card)
        .fontDesign(.rounded)
        .tint(Theme.ink)
        .task {
            guard let id = video.id else { step = .nothing; return }
            do {
                batches = Calibration.batches(of: try await env.database.calibrationWords(videoID: id))
                if batches.isEmpty { step = .nothing } else { step = .asking; await loadGlosses() }
            } catch { self.error = Problem(error, fallback: String(localized: "Kikimi couldn't load these words.")); step = .nothing }
        }
    }

    // MARK: Asking

    private var asking: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("I know these words").font(Theme.title(20))
                Text("Tick the words you know. Only those are marked as known, which makes this video's figure and your lessons truer.")
                    .font(Theme.copy).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(batch) { word in chip(word) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            Text(index < batches.count - 1 && !canContinue
                 ? String(localized: "Know at least half of these to be shown more words.")
                 : String(localized: "Words \(index * Calibration.batchSize + 1) to \(index * Calibration.batchSize + batch.count) of \(batches.reduce(0) { $0 + $1.count }), the most common in this video."))
                .font(Theme.copy).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(.pill(.quiet, compact: true))
                Button(allTicked ? "Clear all" : "Select all") {
                    if allTicked { ticked.subtract(batch.map(\.id)) } else { ticked.formUnion(batch.map(\.id)) }
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Spacer()
                if index < batches.count - 1 {
                    Button("Next \(min(Calibration.batchSize, batches[index + 1].count)) words") { advance() }
                        .buttonStyle(.pill(.secondary, compact: true)).disabled(!canContinue)
                        .keyboardShortcut(canContinue ? .defaultAction : nil)
                }
                finishButton.keyboardShortcut(canContinue ? nil : .defaultAction)
            }
        }
    }

    /// Marks what is ticked, in one step. With nothing ticked it only closes.
    @ViewBuilder private var finishButton: some View {
        if toMark.isEmpty {
            Button("Done") { dismiss() }.buttonStyle(.pill(compact: true))
        } else {
            Button(inflected("Mark ^[\(toMark.count) word](inflect: true) as known")) { Task { await mark() } }
                .buttonStyle(.pill(canContinue ? .secondary : .primary, compact: true))
                .help("They are left out of lessons and count toward how much of each video you know. You can undo it right after.")
        }
    }

    private var allTicked: Bool { !batch.isEmpty && batch.allSatisfy { ticked.contains($0.id) } }

    /// One word. Tapping marks it as known to you, shown by the fill and the tick, not by colour alone.
    private func chip(_ word: CalibrationWord) -> some View {
        let isKnown = ticked.contains(word.id)
        return Button {
            if isKnown { ticked.remove(word.id) } else { ticked.insert(word.id) }
        } label: {
            HStack(spacing: 5) {
                Text(word.lemma).font(Theme.sized(size: 16, weight: .medium, design: .rounded))
                if isKnown { Image(systemName: "checkmark").font(Theme.sized(size: 10, weight: .bold)).accessibilityHidden(true) }
            }
            .foregroundStyle(isKnown ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(isKnown ? Theme.ink : Theme.soft))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(glosses[word.id] ?? "")
        .accessibilityLabel([word.lemma, glosses[word.id]].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(isKnown ? String(localized: "Known") : String(localized: "Not ticked"))
        .accessibilityAddTraits(isKnown ? .isSelected : [])
    }

    private func advance() {
        index += 1
        Task { await loadGlosses() }
    }

    /// The first meaning of each word in the batch on screen, as a hint on hover and for VoiceOver.
    private func loadGlosses() async {
        for word in batch where glosses[word.id] == nil {
            let entry = try? await env.database.lookup(language: video.language, term: word.lemma, limit: 1).first
            glosses[word.id] = entry?.shortGloss
        }
    }

    private func mark() async {
        let ids = toMark
        do {
            let before = try await env.database.snapshot(of: ids)   // so Undo can put each word back as it was
            let n = try await env.database.markKnown(wordIDs: ids)
            app.dataChanged()
            dismiss()
            app.showToast(inflected("Marked ^[\(n) word](inflect: true) as known"), undo: (String(localized: "Undo"), {
                Task {
                    try? await env.database.restore(before)
                    app.dataChanged()
                    app.showToast(String(localized: "Undone"))
                }
            }))
        } catch { self.error = Problem(error, fallback: String(localized: "Kikimi couldn't mark those words as known. Try again.")) }
    }

    // MARK: Nothing to ask

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing to ask").font(Theme.title(20))
            Text("Every word in this video has already been set, whether learning, known or ignored.")
                .font(Theme.copy).foregroundStyle(Theme.muted)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction) }
        }
    }
}
