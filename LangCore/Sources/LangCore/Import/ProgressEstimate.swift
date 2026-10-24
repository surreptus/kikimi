import Foundation

/// How long a step has left, judged by how fast it has gone so far. It says nothing until there is something to judge
/// by, because an early guess swings wildly.
public enum ProgressEstimate {
    /// Seconds left, or nil if it is too early (under 5% done, or under 8 seconds in) or the step is finished.
    public static func secondsLeft(elapsed: TimeInterval, fraction: Double) -> TimeInterval? {
        guard fraction >= 0.05, fraction < 1, elapsed >= 8 else { return nil }
        return elapsed * (1 - fraction) / fraction
    }

    /// "less than a minute left", "about 3 min left", "about 1 h 10 min left". Rounded, because it is an estimate:
    /// to the minute under ten minutes, to five minutes above.
    public static func phrase(secondsLeft: TimeInterval) -> String {
        let seconds = max(0, secondsLeft)
        if seconds < 45 { return "less than a minute left" }
        if seconds < 90 { return "about 1 min left" }
        let minutes = seconds / 60
        let rounded = minutes < 10 ? Int(minutes.rounded()) : Int((minutes / 5).rounded()) * 5
        if rounded < 60 { return "about \(rounded) min left" }
        let hours = rounded / 60, rest = rounded % 60
        return rest == 0 ? "about \(hours) h left" : "about \(hours) h \(rest) min left"
    }
}
