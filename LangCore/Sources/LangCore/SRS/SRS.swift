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

    /// How far an interval may move, as a share of it. Words learned together then come back over a spread of time, not as one pile.
    public static let variation = 0.1

    /// A random number from -1 to 1 for `answer(jitter:)`. Tests pass a seeded generator.
    public static func randomJitter<G: RandomNumberGenerator>(using generator: inout G) -> Double {
        Double.random(in: -1...1, using: &generator)
    }

    public static func randomJitter() -> Double {
        var generator = SystemRandomNumberGenerator()
        return randomJitter(using: &generator)
    }

    /// The interval moved by `jitter` (-1...1) times `variation`. It is never shorter than the stage-1 interval,
    /// so no card is asked before its first wait is over.
    public static func interval(for stage: SRSStage, jitter: Double) -> TimeInterval? {
        guard let base = interval(for: stage) else { return nil }
        let moved = base * (1 + variation * min(1, max(-1, jitter)))
        return max(intervals[0], moved)
    }

    /// Correct advances one stage, wrong drops one (never below stage 1).
    /// Finished is terminal. `nextReview` is nil once finished. The default `jitter` of 0 gives the exact interval.
    public static func answer(
        stage: SRSStage, correct: Bool, now: Date, jitter: Double = 0
    ) -> (stage: SRSStage, nextReview: Date?) {
        guard stage != .finished else { return (.finished, nil) }
        let next = correct
            ? SRSStage(rawValue: stage.rawValue + 1)!
            : SRSStage(rawValue: max(1, stage.rawValue - 1))!
        return (next, interval(for: next, jitter: jitter).map { now.addingTimeInterval($0) })
    }
}
