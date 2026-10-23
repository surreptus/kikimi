import Foundation

/// WaniKani-style stages: apprentice 1-4, guru 1-2, master, enlightened, burned.
public enum SRSStage: Int, Codable, CaseIterable, Comparable, Sendable {
    case apprentice1 = 1, apprentice2, apprentice3, apprentice4
    case guru1, guru2, master, enlightened, burned

    public static func < (a: SRSStage, b: SRSStage) -> Bool { a.rawValue < b.rawValue }
}

public enum SRS {
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 24 * 3600

    /// Wait before the next review, indexed by stage 1...8. Burned has none.
    public static let intervals: [TimeInterval] = [
        4 * hour, 8 * hour, 23 * hour, 47 * hour, 7 * day, 14 * day, 30 * day, 120 * day,
    ]

    public static func interval(for stage: SRSStage) -> TimeInterval? {
        stage == .burned ? nil : intervals[stage.rawValue - 1]
    }

    /// Correct advances one stage, wrong drops one (never below apprentice 1).
    /// Burned is terminal. `nextReview` is nil once burned.
    public static func answer(
        stage: SRSStage, correct: Bool, now: Date
    ) -> (stage: SRSStage, nextReview: Date?) {
        guard stage != .burned else { return (.burned, nil) }
        let next = correct
            ? SRSStage(rawValue: stage.rawValue + 1)!
            : SRSStage(rawValue: max(1, stage.rawValue - 1))!
        return (next, interval(for: next).map { now.addingTimeInterval($0) })
    }
}
