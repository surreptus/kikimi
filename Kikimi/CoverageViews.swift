import LangCore
import SwiftUI

/// How much of a video you already know: a short bar, the percentages and a word for it. Known words are a solid segment
/// and learning words (stages 1 to 4) a lighter one after it. The segments differ in fill and length, and the text gives
/// both figures, so nothing depends on colour. The fit word counts known words only.
struct CoverageBadge: View {
    let coverage: VideoCoverage?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        if let coverage, let fit = coverage.fit {
            HStack(spacing: 8) {
                bar(coverage)
                Text(summary(coverage, fit: fit))
                    .font(Theme.small).foregroundStyle(Theme.ink)
            }
            .help("You know \(coverage.knownWords) of this video's \(coverage.totalWords) content words (counted once per line). In our samples, knowing 90% of the content words was about 94% to 96% of everything said (counting the small words as known), around where listening becomes comfortable. This counts the words you know, not how much you understand: grammar, idioms, speed and the transcript's mistakes matter too. Words you are learning at Stages 1 to 4 are shown beside it and do not count as known. Words you ignore are left out of the count.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(coverage, fit: fit))
        } else {
            Text("No words found").font(Theme.small).foregroundStyle(Theme.muted)
        }
    }

    private static let barWidth: CGFloat = 64

    /// A solid known segment, then a lighter learning one, on a faint track. Both are clipped to the track. With Increase
    /// Contrast or Differentiate Without Colour on, the learning segment gets thin diagonal lines in full ink, so it
    /// differs by pattern as well as by tint.
    private func bar(_ coverage: VideoCoverage) -> some View {
        let known = max(5, Self.barWidth * coverage.fraction)
        let learning = coverage.learningWords > 0 ? max(3, Self.barWidth * coverage.learningFraction) : 0
        let hatched = contrast == .increased || differentiateWithoutColor
        let reach = min(Self.barWidth, known + learning)
        return ZStack(alignment: .leading) {
            Capsule().fill(Theme.ink.opacity(0.15))
            Capsule().fill(Theme.ink.opacity(hatched ? 0.25 : 0.45)).frame(width: reach)
            if hatched && learning > 0 {
                // The known segment is drawn over the start of this, so only the learning part shows lines.
                Canvas { context, size in
                    var lines = Path()
                    var x: CGFloat = -size.height
                    while x < size.width {
                        lines.move(to: CGPoint(x: x, y: size.height)); lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 3
                    }
                    context.stroke(lines, with: .color(Theme.ink), lineWidth: 1)
                }
                .frame(width: reach, height: 6)
                .clipShape(Capsule())
            }
            Capsule().fill(Theme.ink).frame(width: known)
        }
        .frame(width: Self.barWidth, height: 6)
    }

    private func summary(_ coverage: VideoCoverage, fit: LevelFit) -> String {
        let known = percent(coverage.fraction)
        guard coverage.learningWords > 0 else { return String(localized: "\(known) of words known · \(fit.title)") }
        let learning = percent(coverage.learningFraction)
        return String(localized: "\(known) of words known, \(learning) learning · \(fit.title)")
    }

    private func accessibilityText(_ coverage: VideoCoverage, fit: LevelFit) -> String {
        let known = percent(coverage.fraction)
        guard coverage.learningWords > 0 else { return String(localized: "Known-word coverage \(known): \(fit.title)") }
        let learning = percent(coverage.learningFraction)
        return String(localized: "Known-word coverage \(known), learning \(learning): \(fit.title)")
    }

    private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}

/// What it would take to reach a coverage: the words, and a button to learn the ones not started yet, in lessons.
struct CoverageGoalView: View {
    let goal: CoverageGoal
    let learn: ([CoverageGoal.Entry]) -> Void
    /// Opens the pass where you tap the words you don't know and the rest are marked known.
    var markKnown: (() -> Void)?

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
                    HStack(spacing: 10) {
                        Button(inflected("Learn ^[\(fresh.count) word](inflect: true) in lessons")) { learn(fresh) }
                            .buttonStyle(.pill(compact: true))
                        if let markKnown {
                            Button("Mark the words I know…", action: markKnown).buttonStyle(.pill(.quiet, compact: true))
                        }
                    }
                }
            }
        }
    }
}
