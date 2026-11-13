import LangCore
import SwiftUI

/// "I know these words" for one video: its most-seen new words in batches of twenty, where you tick the ones you know. It
/// stops once fewer than half of a batch are known, then says how many words it will mark known, and only marks them when
/// you say so. The rules (the batches, when to stop, which words end up known) are in `Calibration`.
struct CalibrationSheet: View {
    let env: LangEnvironment
    let video: Video
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    private enum Step { case loading, asking, confirming, nothing }
    @State private var step = Step.loading
    @State private var batches: [[CalibrationWord]] = []
    @State private var index = 0
    @State private var ticked: Set<Int64> = []
    @State private var glosses: [Int64: String] = [:]
    @State private var error: String?

    private var batch: [CalibrationWord] { batches.indices.contains(index) ? batches[index] : [] }
    private var isLast: Bool { index >= batches.count - 1 || Calibration.endsAfter(batch, known: ticked) }
    private var toMark: [Int64] { Calibration.known(shown: Array(batches.prefix(index + 1)), ticked: ticked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            case .nothing: nothing
            case .asking: asking
            case .confirming: confirming
            }
            if let error { Text(error).font(Theme.small).foregroundStyle(Theme.red) }
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
            } catch { self.error = error.localizedDescription; step = .nothing }
        }
    }

    // MARK: Asking

    private var asking: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("I know these words").font(Theme.title(20))
                Text("Tick the words you know. Only those are marked as known, which makes this video's figure and your lessons truer.")
                    .font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(batch) { word in chip(word) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            Text(Calibration.endsAfter(batch, known: ticked) && !ticked.isEmpty
                 ? String(localized: "Fewer than half of these are known to you, so that is enough.")
                 : String(localized: "Words \(index * Calibration.batchSize + 1) to \(index * Calibration.batchSize + batch.count), the most common in this video."))
                .font(Theme.small).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(.pill(.quiet, compact: true))
                Button(allTicked ? "Clear all" : "Select all") {
                    if allTicked { ticked.subtract(batch.map(\.id)) } else { ticked.formUnion(batch.map(\.id)) }
                }
                .buttonStyle(.pill(.secondary, compact: true))
                Spacer()
                if isLast {
                    Button("Review") { step = .confirming }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Next \(min(Calibration.batchSize, batches[index + 1].count)) words") { advance() }
                        .buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
                }
            }
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

    // MARK: Confirming

    private var confirming: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(toMark.isEmpty ? "Nothing to mark" : "Mark \(inflected("^[\(toMark.count) word](inflect: true)")) as known?").font(Theme.title(20))
            Text(toMark.isEmpty
                 ? "You ticked no words, so none are marked known."
                 : "These are the words you ticked. They are marked as known, so they are left out of lessons and count toward how much of each video you know. You can undo it right after.")
                .font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Back") { step = .asking }.buttonStyle(.pill(.quiet, compact: true))
                Spacer()
                if toMark.isEmpty {
                    Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.buttonStyle(.pill(.secondary, compact: true))
                    Button("Mark known") { Task { await mark() } }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
                }
            }
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
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Nothing to ask

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing to ask").font(Theme.title(20))
            Text("Every word in this video has already been set, whether learning, known or ignored.")
                .font(Theme.small).foregroundStyle(Theme.muted)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction) }
        }
    }
}
