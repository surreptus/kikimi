import GRDB
import XCTest
@testable import LangCore

final class PunctuationWordsTests: XCTestCase {
    func testOnlyUntouchedPunctuationWordsAreRemoved() throws {
        let queue = try DatabaseQueue()
        let migrator = LangMigrations.migrator()
        try migrator.migrate(queue, upTo: "v6-translations")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO videos (language, title, content_hash, video_path, duration, imported_at) VALUES ('ja','v','h','h/v.mov',9,0)")
            try db.execute(sql: "INSERT INTO subtitles (video_id, idx, start_time, end_time, text) VALUES (1,0,0,1,'本当?')")
            for (lemma, status) in [("!", "new"), ("?", "new"), ("?!", "learning"), ("本当", "new"), ("123", "new")] {
                try db.execute(sql: "INSERT INTO words (language, lemma, pos, status) VALUES ('ja', ?, 'noun', ?)",
                               arguments: [lemma, status])
            }
        }
        try queue.write { db in
            for word in 1...5 {
                try db.execute(sql: "INSERT INTO occurrences (word_id, subtitle_id, surface) VALUES (?, 1, 'x')", arguments: [word])
            }
        }
        try migrator.migrate(queue)
        let left = try queue.read { try String.fetchAll($0, sql: "SELECT lemma FROM words ORDER BY lemma") }
        XCTAssertEqual(Set(left), ["?!", "本当", "123"], "a word you chose to learn stays, even if it is punctuation")
        let occurrences = try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM occurrences") }
        XCTAssertEqual(occurrences, 3, "the removed words' occurrences went with them")
    }
}
