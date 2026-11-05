import GRDB
import XCTest
@testable import LangCore

final class PunctuationWordsTests: XCTestCase {
    func testOnlyUntouchedPunctuationWordsAreRemoved() throws {
        let queue = try DatabaseQueue()
        let migrator = LangMigrations.migrator()
        try migrator.migrate(queue, upTo: "v6-translations")
        try queue.write { db in
            for (lemma, status) in [("!", "new"), ("?", "new"), ("?!", "learning"), ("本当", "new"), ("123", "new")] {
                try db.execute(sql: "INSERT INTO words (language, lemma, pos, status) VALUES ('ja', ?, 'noun', ?)",
                               arguments: [lemma, status])
            }
        }
        try migrator.migrate(queue)
        let left = try queue.read { try String.fetchAll($0, sql: "SELECT lemma FROM words ORDER BY lemma") }
        XCTAssertEqual(Set(left), ["?!", "本当", "123"], "a word you chose to learn stays, even if it is punctuation")
    }
}
