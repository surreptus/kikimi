import Foundation

/// Maps a playback time to the subtitle line to highlight.
public struct SubtitleTimeline: Sendable {
    public let lines: [Subtitle]
    /// How long after a line ends it stays highlighted before the timeline goes quiet.
    public let grace: Double

    public init(_ lines: [Subtitle], grace: Double = 1.0) {
        self.lines = lines.sorted { $0.startTime < $1.startTime }
        self.grace = grace
    }

    /// The latest line that has started, unless playback is past its end by more than `grace`.
    public func index(at time: Double) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].startTime <= time { low = mid + 1 } else { high = mid }
        }
        let candidate = low - 1
        guard candidate >= 0, time <= lines[candidate].endTime + grace else { return nil }
        return candidate
    }
}
