import Foundation
import GRDB

extension LangDatabase {
    /// Up to `count` words you marked known, chosen at random.
    public func knownSample(language: String, count: Int) async throws -> [Int64] {
        try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT id FROM words WHERE language = ? AND status = 'known' ORDER BY RANDOM() LIMIT ?
                """, arguments: [language, count])
        }
    }
}
