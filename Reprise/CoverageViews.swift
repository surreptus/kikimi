import LangCore
import SwiftUI

/// How much of a video you already know: a short bar, the percentage and a word for it. The bar's length and the word
/// carry the meaning, so it never depends on colour.
struct CoverageBadge: View {
    let coverage: VideoCoverage?

    var body: some View {
        if let coverage, let fit = coverage.fit {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.15))
                    Capsule().fill(Theme.ink).frame(width: max(5, 64 * coverage.fraction))
                }
                .frame(width: 64, height: 6)
                Text("\(percent(coverage)) known · \(fit.title)")
                    .font(Theme.small).foregroundStyle(Theme.ink)
            }
            .help("You know \(coverage.knownWords) of this video's \(coverage.totalWords) content words (counted once per line). About 90% of content words is roughly 95% of everything said, around where listening becomes comfortable.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You know \(percent(coverage)) of its words: \(fit.title)")
        } else {
            Text("No words found").font(Theme.small).foregroundStyle(Theme.muted)
        }
    }

    private func percent(_ coverage: VideoCoverage) -> String { "\(Int((coverage.fraction * 100).rounded()))%" }
}

/// What it would take to reach a coverage: the words, and a button to start learning the ones not started yet.
struct CoverageGoalView: View {
    let goal: CoverageGoal
    let startLearning: ([CoverageGoal.Entry]) -> Void
    let message: String?

    private var targetPercent: String { "\(Int((goal.target * 100).rounded()))%" }
    private var currentPercent: String { "\(Int((goal.current.fraction * 100).rounded()))%" }

    /// What learning these words would do, and how many are already in your reviews.
    private func goalText(count: Int, notStarted: Int) -> String {
        let what = count == 1
            ? String(localized: "Learn the word you don't know yet and this video goes from \(currentPercent) to about \(targetPercent).")
            : String(localized: "Learn the \(count) most common words you don't know yet and this video goes from \(currentPercent) to about \(targetPercent).")
        guard notStarted < count else { return what }
        return what + " " + String(localized: "\(count - notStarted) already in your reviews.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverageBadge(coverage: goal.current)
            if goal.isReached {
                Text("You already know \(currentPercent) of this video's words. Nothing more is needed to follow it comfortably.")
                    .foregroundStyle(Theme.muted)
            } else {
                let count = goal.words.count, fresh = goal.notStarted
                Text(goalText(count: count, notStarted: fresh.count))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !fresh.isEmpty {
                    Text(fresh.prefix(8).map { "\($0.lemma) ×\($0.occurrences)" }.joined(separator: "   ") + (fresh.count > 8 ? "   " + String(localized: "and \(fresh.count - 8) more") : ""))
                        .font(Theme.small).foregroundStyle(Theme.ink)
                    Button(inflected("Start learning ^[\(fresh.count) word](inflect: true)")) { startLearning(fresh) }
                        .buttonStyle(.pill(compact: true))
                }
            }
            if let message { Text(message).font(Theme.small).foregroundStyle(Theme.ink) }
        }
    }
}
