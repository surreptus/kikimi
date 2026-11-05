import Foundation
import GRDB

/// Extra study that moves nothing: the words are asked as in a review, but no stage changes and a miss is not asked again.
public enum PracticeKind: Sendable {
    /// Words being learned that are not due yet, soonest first.
    case ahead
    /// Words that have been through every stage.
    case finished
}

extension LangDatabase {
    /// Up to `count` words for extra study of `kind`.
    public func practiceSample(_ kind: PracticeKind, language: String, count: Int, now: Date = Date()) async throws -> [Int64] {
        try await writer.read { db in
            switch kind {
            case .ahead:
                try Int64.fetchAll(db, sql: """
                    SELECT id FROM words WHERE language = ? AND status = 'learning' AND next_review > ?
                    ORDER BY next_review LIMIT ?
                    """, arguments: [language, now, count])
            case .finished:
                try Int64.fetchAll(db, sql: """
                    SELECT id FROM words WHERE language = ? AND status = ? ORDER BY RANDOM() LIMIT ?
                    """, arguments: [language, WordStatus.finished.rawValue, count])
            }
        }
    }

    /// Up to `count` words you marked known, chosen at random.
    public func knownSample(language: String, count: Int) async throws -> [Int64] {
        try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT id FROM words WHERE language = ? AND status = 'known' ORDER BY RANDOM() LIMIT ?
                """, arguments: [language, count])
        }
    }
}
