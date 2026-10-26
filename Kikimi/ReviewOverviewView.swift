import LangCore
import SwiftUI

/// The review page before a session: what is ready, what is coming, and where your words stand.
struct ReviewOverviewView: View {
    let overview: ReviewOverview
    let start: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ready
                comingUp
                stages
            }
            .frame(maxWidth: 640)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Ready now

    private var ready: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(overview.dueNow)").font(.system(size: 44, weight: .semibold, design: .rounded))
                Text(overview.dueNow == 0 ? nextText : inflected("^[\(overview.dueNow) review](inflect: true) ready"))
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Start reviewing") { start() }
                .buttonStyle(.pill(.primary))
                .keyboardShortcut(.space, modifiers: [])
                .disabled(overview.dueNow == 0)
        }
        .panel()
    }

    /// "Next review in 3 hours", or that nothing is scheduled.
    private var nextText: String {
        guard let next = overview.nextReview else { return String(localized: "Nothing scheduled yet") }
        return String(localized: "Next review \(next.formatted(.relative(presentation: .numeric)))")
    }

    // MARK: Coming up

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming up").font(Theme.title(17))
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(overview.byDay.enumerated()), id: \.offset) { index, count in bar(index, count) }
            }
            .frame(height: 110)
            if overview.afterThat > 0 {
                Text("^[\(overview.afterThat) more review](inflect: true) after that")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
    }

    private func bar(_ index: Int, _ count: Int) -> some View {
        let tallest = max(1, overview.byDay.max() ?? 1)
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(count)").font(Theme.small).foregroundStyle(count == 0 ? Theme.faint : Theme.ink)
            Capsule().fill(index == 0 ? Theme.ink : Theme.ink.opacity(0.35))
                .frame(height: max(4, 64 * CGFloat(count) / CGFloat(tallest)))
            Text(dayName(index)).font(Theme.small).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dayName(index, long: true)): \(inflected("^[\(count) review](inflect: true)"))")
    }

    private func dayName(_ index: Int, long: Bool = false) -> String {
        if index == 0 { return String(localized: "Today") }
        let date = Calendar.current.date(byAdding: .day, value: index, to: Date()) ?? Date()
        return date.formatted(.dateTime.weekday(long ? .wide : .abbreviated))
    }

    // MARK: Where your words are

    private var stages: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your words are").font(Theme.title(17))
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 6) {
                        StageRing(stage: i + 1, size: 24)
                        Text("\(overview.perStage[i])").font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("\(i + 1)").font(Theme.small).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Stage \(i + 1): \(inflected("^[\(overview.perStage[i]) word](inflect: true)"))")
                }
            }
            Text("\(overview.learning) learning · \(overview.known) known · \(overview.finished) finished")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
