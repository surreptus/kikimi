import Foundation
import GRDB

/// How often a word has turned up in your videos.
public struct WordSeen: Equatable, Sendable {
    /// Subtitle lines that contain the word (once per line, however often it is said in it).
    public var lines = 0
    public var videos = 0

    public init(lines: Int = 0, videos: Int = 0) { self.lines = lines; self.videos = videos }
}

extension LangDatabase {
    public func seen(wordID: Int64) async throws -> WordSeen {
        try await writer.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT occurrences.subtitle_id) AS lines, COUNT(DISTINCT subtitles.video_id) AS videos
                FROM occurrences JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                WHERE occurrences.word_id = ?
                """, arguments: [wordID])
            return WordSeen(lines: row?["lines"] ?? 0, videos: row?["videos"] ?? 0)
        }
    }
}
