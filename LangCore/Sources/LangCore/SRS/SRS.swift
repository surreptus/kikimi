import Foundation

/// Eight review stages, then finished. The stored values are the raw numbers 1...9, so renaming a case never touches saved data.
public enum SRSStage: Int, Codable, CaseIterable, Comparable, Sendable {
    case stage1 = 1, stage2, stage3, stage4, stage5, stage6, stage7, stage8, finished

    public static func < (a: SRSStage, b: SRSStage) -> Bool { a.rawValue < b.rawValue }
}

public enum SRS {
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 24 * 3600

    /// Wait before the next review, indexed by stage 1...8. Finished has none.
    public static let intervals: [TimeInterval] = [
        4 * hour, 8 * hour, 23 * hour, 47 * hour, 7 * day, 14 * day, 30 * day, 120 * day,
    ]

    public static func interval(for stage: SRSStage) -> TimeInterval? {
        stage == .finished ? nil : intervals[stage.rawValue - 1]
    }

    /// Correct advances one stage, wrong drops one (never below stage 1).
    /// Finished is terminal. `nextReview` is nil once finished.
    public static func answer(
        stage: SRSStage, correct: Bool, now: Date
    ) -> (stage: SRSStage, nextReview: Date?) {
        guard stage != .finished else { return (.finished, nil) }
        let next = correct
            ? SRSStage(rawValue: stage.rawValue + 1)!
            : SRSStage(rawValue: max(1, stage.rawValue - 1))!
        return (next, interval(for: next).map { now.addingTimeInterval($0) })
    }
}
