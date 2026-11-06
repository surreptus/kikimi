import LangCore
import SwiftUI

/// Study on top of the schedule. Only a known check can change a word (a miss sends it back to learning).
enum ExtraStudy: Hashable {
    case ahead, known, finished
    /// The quiz at the end of a lesson: not offered in Practice, only run by a lesson.
    case lesson

    static let practiceKinds: [ExtraStudy] = [.ahead, .known, .finished]

    var title: LocalizedStringKey {
        switch self {
        case .ahead: "Review ahead"
        case .known: "Review known"
        case .finished: "Practice finished"
        case .lesson: "Lesson quiz"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .ahead: "Words you are learning that are not due yet. Nothing moves, whatever you answer."
        case .known: "A quick test of a few words you marked known. Any you miss go back to your reviews, so the numbers stay honest."
        case .finished: "Words that have been through every stage. Nothing moves, whatever you answer."
        case .lesson: "The words you were just taught, asked at once."
        }
    }
}

/// The learn page before a session: what is ready, what to practise, what is coming, and where your words stand.
struct ReviewOverviewView: View {
    let overview: ReviewOverview
    let lessons: DailyLessons?
    let stats: LearningStats?
    @Binding var style: ReviewStyle
    @State private var sentenceAnswer: ReviewAnswer = .check
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let startLessons: () -> Void
    let start: () -> Void
    let practise: (ExtraStudy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                lessonsCard
                reviewsCard
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

    /// Today's new words, taught a few at a time and quizzed at once. Shown when there are some to learn, or to say why
    /// there are none. It is the accent colour, so the two things to do here (a lesson, a review) are told apart at a glance.
    @ViewBuilder
    private var lessonsCard: some View {
        if let lessons, !lessons.isOff, !lessons.wordIDs.isEmpty || lessons.heldBack || lessons.startedToday > 0 {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Lessons").font(Theme.title(24))
                        count(lessons.wordIDs.count, onAccent: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lessons")
                    .accessibilityValue(inflected("^[\(lessons.wordIDs.count) new word](inflect: true) to learn"))
                    Text(lessonsCaption(lessons)).font(Theme.small).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Start") { startLessons() }
                    .buttonStyle(.pill(.inverted, compact: true))
                    .disabled(lessons.wordIDs.isEmpty)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.accent))
        }
    }

    private func lessonsCaption(_ lessons: DailyLessons) -> String {
        if lessons.heldBack {
            return inflected("^[\(overview.dueNow) review](inflect: true) are due. New words wait until fewer than \(LangDatabase.lessonReviewLimit) are, so they don't pile up.")
        }
        if lessons.wordIDs.isEmpty {
            return inflected("You started ^[\(lessons.startedToday) new word](inflect: true) today. More tomorrow.")
        }
        return String(localized: "The new words you hear most in your videos, \(DailyLessons.batchSize) at a time: you are taught them, then asked them at once.")
    }

    /// The number beside a panel's title: filled when there is something to do.
    private func count(_ n: Int, onAccent: Bool = false) -> some View {
        Text("\(n)")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(onAccent ? Theme.accent : (n == 0 ? Theme.ink : Theme.onAccent))
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(Capsule().fill(onAccent ? Theme.onAccent : (n == 0 ? Theme.ink.opacity(0.12) : Theme.accent)))
    }

    // MARK: Ready now

    /// What is ready to review: the title and its count, Start, and the kind of card that reviews and practice use.
    private var reviewsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Reviews").font(Theme.title(24))
                    count(overview.dueNow)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reviews")
                .accessibilityValue(inflected("^[\(overview.dueNow) review](inflect: true) ready"))
                Spacer(minLength: 0)
                Button("Start") { start() }
                    .buttonStyle(.pill(.primary, compact: true))
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(overview.dueNow == 0)
            }
            if overview.dueNow == 0 { Text(nextText).font(Theme.small).foregroundStyle(Theme.muted) }

            IconSegmentedPicker(
                options: ReviewPrompt.allCases.map { .init(value: $0, title: $0.shortTitle, fullTitle: $0.title, symbol: $0.symbol) },
                selection: promptChoice)
                .accessibilityLabel("Card type")
                .help("A word with no sentence from your videos (or no short one, for typing) is asked as word and meaning.")
            // Only a sentence can be answered more than one way.
            if style.prompt == .sentence {
                Menu {
                    Picker("How you answer", selection: answerChoice) {
                        ForEach(ReviewAnswer.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Label(style.answer.title, systemImage: style.answer.symbol)
                }
                .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).fixedSize()
                .accessibilityLabel("How you answer")
                .help("How you answer a sentence card")
            }
            Text(style.summary).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                .id(style)   // a new line for each choice, which fades in as the panel resizes
                .transition(.opacity)
            Text("The card type is used for reviews and practice, not for lessons.").font(Theme.small).foregroundStyle(Theme.muted)
            practice
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .animation(reduceMotion ? nil : Theme.easeOut(0.18), value: style)
        .onAppear { if style.prompt == .sentence { sentenceAnswer = style.answer } }
    }

    /// The card type; choosing a sentence keeps the way of answering it that was used last.
    private var promptChoice: Binding<ReviewPrompt> {
        Binding(
            get: { style.prompt },
            set: { style = ReviewStyle(prompt: $0, answer: $0 == .sentence ? sentenceAnswer : .check) ?? .meaning })
    }

    private var answerChoice: Binding<ReviewAnswer> {
        Binding(
            get: { style.answer },
            set: { sentenceAnswer = $0; style = ReviewStyle(prompt: .sentence, answer: $0) ?? .listening })
    }

    /// "Next review in 3 hours", or that nothing is scheduled.
    private var nextText: String {
        guard let next = overview.nextReview else { return String(localized: "Nothing scheduled yet") }
        return String(localized: "Next review \(next.formatted(.relative(presentation: .numeric)))")
    }

    // MARK: Practice

    /// Extra study that does not move the schedule (a known check can send a missed word back), inside the Reviews panel
    /// because it uses the same card type. A row is shown only when there is enough to practise; its button is quiet,
    /// since it is something you do again and again.
    @ViewBuilder
    private var practice: some View {
        let rows = ExtraStudy.practiceKinds.filter { count($0) >= minimum($0) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Text("Practice").font(Theme.title(17)).accessibilityAddTraits(.isHeader)
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
                            .buttonStyle(.pill(.quiet, compact: true))
                            .accessibilityLabel(kind.title)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func count(_ kind: ExtraStudy) -> Int {
        switch kind {
        case .ahead: overview.learning - overview.dueNow
        case .known: overview.known
        case .finished: overview.finished
        case .lesson: 0
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
            Text("Under each ring: how long until a word at that stage comes back. Get it right to move up a stage, miss it to drop one; after stage 8 a word is Finished and no longer comes back for review.")
                .font(Theme.small).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
