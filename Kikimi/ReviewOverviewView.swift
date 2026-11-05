import LangCore
import SwiftUI

/// Study on top of the schedule. Only a known check can change a word (a miss sends it back to learning).
enum ExtraStudy: Hashable, CaseIterable {
    case ahead, known, finished

    var title: LocalizedStringKey {
        switch self {
        case .ahead: "Review ahead"
        case .known: "Review known"
        case .finished: "Practice finished"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .ahead: "Words you are learning that are not due yet. Nothing moves, whatever you answer."
        case .known: "A quick test of a few words you marked known. Any you miss go back to your reviews, so the numbers stay honest."
        case .finished: "Words that have been through every stage. Nothing moves, whatever you answer."
        }
    }
}

/// The learn page before a session: what is ready, what to practise, what is coming, and where your words stand.
struct ReviewOverviewView: View {
    let overview: ReviewOverview
    let lessons: DailyLessons?
    let stats: LearningStats?
    @Binding var style: ReviewStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let startLessons: () -> Void
    let start: () -> Void
    let practise: (ExtraStudy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                lessonsCard
                ready
                practice
                comingUp
                stages
                if let stats { progress(stats) }
            }
            .frame(maxWidth: 640)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Lessons

    /// Today's new words. Shown when there are some to learn, or to say why there are none.
    @ViewBuilder
    private var lessonsCard: some View {
        if let lessons, !lessons.isOff, !lessons.wordIDs.isEmpty || lessons.heldBack || lessons.startedToday > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Lessons").font(Theme.title(24))
                        count(lessons.wordIDs.count)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lessons")
                    .accessibilityValue(inflected("^[\(lessons.wordIDs.count) lesson](inflect: true) ready"))
                    Spacer()
                    Button("Start") { startLessons() }
                        .buttonStyle(.pill(.primary, compact: true))
                        .disabled(lessons.wordIDs.isEmpty)
                }
                Text(lessonsCaption(lessons)).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .panel()
        }
    }

    private func lessonsCaption(_ lessons: DailyLessons) -> String {
        if lessons.heldBack {
            return inflected("^[\(overview.dueNow) review](inflect: true) are due. New words wait until fewer than \(LangDatabase.lessonReviewLimit) are, so they don't pile up.")
        }
        if lessons.wordIDs.isEmpty {
            return inflected("You started ^[\(lessons.startedToday) new word](inflect: true) today. More tomorrow.")
        }
        return String(localized: "The new words you hear most in your videos. Each comes with a sentence to hear, and nothing is added until you press Learn.")
    }

    /// The number beside a panel's title: filled when there is something to do.
    private func count(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(n == 0 ? Theme.ink : Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(Capsule().fill(n == 0 ? Theme.ink.opacity(0.12) : Theme.accent))
    }

    // MARK: Ready now

    /// What is ready (the title and its count), Start, and the kind of card, together. The kind of card also decides
    /// the review of known words.
    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Reviews").font(Theme.title(24))
                    count(overview.dueNow)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reviews")
                .accessibilityValue(inflected("^[\(overview.dueNow) review](inflect: true) ready"))
                Spacer()
                Button("Start") { start() }
                    .buttonStyle(.pill(.primary, compact: true))
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(overview.dueNow == 0)
            }
            if overview.dueNow == 0 { Text(nextText).font(Theme.small).foregroundStyle(Theme.muted) }

            IconSegmentedPicker(
                options: ReviewStyle.allCases.map { .init(value: $0, title: $0.shortTitle, fullTitle: $0.title, symbol: $0.symbol) },
                selection: $style)
                .accessibilityLabel("Card type")
                .help("A word with no sentence from your videos (or no short one, for typing) is asked as word and meaning.")
            Text(style.summary).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                .id(style)   // a new line for each choice, which fades in as the panel resizes
                .transition(.opacity)
            Text("Also used in Practice.").font(Theme.small).foregroundStyle(Theme.muted)
        }
        .panel()
        .animation(reduceMotion ? nil : Theme.easeOut(0.18), value: style)
    }

    /// "Next review in 3 hours", or that nothing is scheduled.
    private var nextText: String {
        guard let next = overview.nextReview else { return String(localized: "Nothing scheduled yet") }
        return String(localized: "Next review \(next.formatted(.relative(presentation: .numeric)))")
    }

    // MARK: Practice

    /// Extra study that does not move the schedule (a known check can send a missed word back). A row is shown only when
    /// there is enough to practise.
    @ViewBuilder
    private var practice: some View {
        let rows = ExtraStudy.allCases.filter { count($0) >= minimum($0) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Practice").font(Theme.title(17))
                ForEach(rows, id: \.self) { kind in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(kind.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text("\(count(kind))").font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                            }
                            Text(kind.summary).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Start") { practise(kind) }
                            .buttonStyle(.pill(.secondary, compact: true))
                            .accessibilityLabel(kind.title)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .accessibilityElement(children: .contain)
        }
    }

    private func count(_ kind: ExtraStudy) -> Int {
        switch kind {
        case .ahead: overview.learning - overview.dueNow
        case .known: overview.known
        case .finished: overview.finished
        }
    }

    /// A known check needs a few words to be a test at all.
    private func minimum(_ kind: ExtraStudy) -> Int { kind == .known ? 3 : 1 }

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
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 6)
                .fill(index == 0 ? Theme.ink : Theme.ink.opacity(0.35))
                .frame(maxWidth: 48)
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

    // MARK: Your progress

    private func progress(_ stats: LearningStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your progress").font(Theme.title(17))
            if stats.isEmpty {
                Text("It builds up here as you watch videos and review words.").font(Theme.small).foregroundStyle(Theme.muted)
            } else {
                HStack(alignment: .top, spacing: 28) {
                    figure(spoken(stats.listenedThisWeek), "listening this week")
                    figure(spoken(stats.listenedTotal), "listening in all")
                    if let accuracy = stats.accuracy {
                        figure("\(Int((accuracy * 100).rounded()))%", "right in reviews, last 30 days")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Words you started learning, by week").font(Theme.small).foregroundStyle(Theme.muted)
                    weeklyBars(stats.startedPerWeek)
                }
                if !stats.mostLookedUp.isEmpty {
                    Text("Looked up most: " + stats.mostLookedUp.map { "\($0.lemma) ×\($0.count)" }.joined(separator: "   "))
                        .font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(label).font(Theme.small).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func weeklyBars(_ counts: [Int]) -> some View {
        let tallest = max(1, counts.max() ?? 1)
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                let start = calendar.date(byAdding: .day, value: -7 * (counts.count - 1 - index), to: thisWeek) ?? thisWeek
                let label = start.formatted(.dateTime.month(.abbreviated).day())
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("\(count)").font(Theme.small).foregroundStyle(count == 0 ? Theme.faint : Theme.ink)
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 6)
                        .fill(index == counts.count - 1 ? Theme.ink : Theme.ink.opacity(0.35))
                        .frame(maxWidth: 40)
                        .frame(height: max(4, 48 * CGFloat(count) / CGFloat(tallest)))
                    Text(label).font(Theme.small).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(label): \(inflected("^[\(count) word](inflect: true)")) started")
            }
        }
        .frame(height: 90)
    }

    /// "45 min", "2 h 10 min".
    private func spoken(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if seconds > 0, minutes == 0 { return String(localized: "1 min") }
        if minutes < 60 { return String(localized: "\(minutes) min") }
        return minutes % 60 == 0 ? String(localized: "\(minutes / 60) h") : String(localized: "\(minutes / 60) h \(minutes % 60) min")
    }

    // MARK: Where your words are

    /// How long until a word at each stage is reviewed again (the intervals in `SRS.intervals`), short and in full.
    private static let gaps: [(short: String, long: String)] = [
        (String(localized: "4h"), String(localized: "4 hours")), (String(localized: "8h"), String(localized: "8 hours")),
        (String(localized: "1d"), String(localized: "1 day")), (String(localized: "2d"), String(localized: "2 days")),
        (String(localized: "1w"), String(localized: "1 week")), (String(localized: "2w"), String(localized: "2 weeks")),
        (String(localized: "1mo"), String(localized: "1 month")), (String(localized: "4mo"), String(localized: "4 months")),
    ]

    private var stages: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your words are").font(Theme.title(17))
            Text("\(overview.learning) learning · \(overview.known) known · \(overview.finished) finished")
                .font(Theme.small).foregroundStyle(Theme.muted)
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 6) {
                        StageRing(stage: i + 1, size: 24)
                        Text("\(overview.perStage[i])").font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(Self.gaps[i].short).font(Theme.small).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Stage \(i + 1), back after \(Self.gaps[i].long): \(inflected("^[\(overview.perStage[i]) word](inflect: true)"))")
                }
            }
            Text("Under each ring: how long until a word at that stage comes back for review.")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
