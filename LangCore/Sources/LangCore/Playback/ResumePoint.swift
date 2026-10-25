import Foundation
import GRDB

/// Whether where you stopped is worth offering to return to: not in the first few seconds, and not at the very end.
public enum ResumePoint {
    public static let ignoreFirst = 5.0
    public static let ignoreLast = 10.0

    /// The position to keep, or nil if the video should simply start from the beginning next time.
    public static func worthKeeping(_ position: Double, duration: Double) -> Double? {
        guard position.isFinite, duration > ignoreFirst + ignoreLast else { return nil }
        return position >= ignoreFirst && position <= duration - ignoreLast ? position : nil
    }
}

extension LangDatabase {
    /// Remembers where `videoID` was stopped (or forgets it, if that is near the start or the end).
    public func saveResumePosition(videoID: Int64, seconds: Double) async throws {
        try await writer.write { db in
            guard var video = try Video.fetchOne(db, key: videoID) else { return }
            let kept = ResumePoint.worthKeeping(seconds, duration: video.duration)
            guard video.resumePosition != kept else { return }
            video.resumePosition = kept
            try video.update(db)
        }
    }
}
