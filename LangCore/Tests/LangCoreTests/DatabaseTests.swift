import XCTest
import GRDB
@testable import LangCore

final class DatabaseTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testMigrationCreatesSchema() throws {
        let db = try LangDatabase()
        let tables = try db.writer.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type='table'") }
        for t in ["videos", "subtitles", "words", "occurrences"] {
            XCTAssertTrue(tables.contains(t), t)
        }
        XCTAssertFalse(tables.contains("dictionary"), "dictionaries are read from their files, not stored here (migration v3)")
    }

    func testMigrationsAreIdempotentAndKeepData() throws {
        let queue = try DatabaseQueue()
        try LangMigrations.migrator().migrate(queue)
        try queue.write { var w = Word(language: "es", lemma: "casa", pos: .noun); try w.insert($0) }

        // Re-running v1 is a no-op; a later migration adds to it without touching v1 data.
        var migrator = LangMigrations.migrator()
        migrator.registerMigration("test-v2") { db in
            try db.alter(table: "words") { $0.add(column: "note", .text) }
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(try Word.fetchCount(db), 1)
            XCTAssertTrue(try db.columns(in: "words").contains { $0.name == "note" })
        }
    }

    func testContentHashIsUnique() throws {
        let db = try LangDatabase()
        func video() -> Video {
            Video(language: "es", title: "a", contentHash: "abc", videoPath: "v", duration: 1)
        }
        try db.writer.write { var v = video(); try v.insert($0) }
        XCTAssertThrowsError(try db.writer.write { var v = video(); try v.insert($0) })
    }

    func testWordKeyIsUniquePerLanguage() throws {
        let db = try LangDatabase()
        try db.writer.write {
            var a = Word(language: "es", lemma: "casa", pos: .noun); try a.insert($0)
            var b = Word(language: "ja", lemma: "casa", pos: .noun); try b.insert($0)
        }
        XCTAssertThrowsError(try db.writer.write { var c = Word(language: "es", lemma: "casa", pos: .noun); try c.insert($0) })
    }

    func testDeletingVideoCascades() throws {
        let db = try LangDatabase()
        try db.writer.write { d in
            var v = Video(language: "es", title: "a", contentHash: "h", videoPath: "v", duration: 1)
            try v.insert(d)
            var s = Subtitle(videoId: v.id!, idx: 0, startTime: 0, endTime: 1, text: "la casa")
            try s.insert(d)
            var w = Word(language: "es", lemma: "casa", pos: .noun)
            try w.insert(d)
            var o = Occurrence(wordId: w.id!, subtitleId: s.id!, surface: "casa")
            try o.insert(d)
            _ = try v.delete(d)
            XCTAssertEqual(try Subtitle.fetchCount(d), 0)
            XCTAssertEqual(try Occurrence.fetchCount(d), 0)
            XCTAssertEqual(try Word.fetchCount(d), 1)
        }
    }

    func testReviewFlow() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d -> Int64 in
            var w = Word(language: "es", lemma: "casa", pos: .noun); try w.insert(d); return w.id!
        }
        try await db.startLearning(wordID: id, now: now)
        var due = try await db.dueWords(language: "es", now: now)
        XCTAssertEqual(due.map(\.id), [id])

        let w = try await db.recordReview(wordID: id, correct: true, now: now)
        XCTAssertEqual(w.stage, .stage2)
        XCTAssertEqual(w.nextReview, now.addingTimeInterval(8 * 3600))
        due = try await db.dueWords(language: "es", now: now)
        XCTAssertTrue(due.isEmpty)

        let w2 = try await db.recordReview(wordID: id, correct: false, now: now)
        XCTAssertEqual(w2.stage, .stage1)
    }

    func testBurnAndKnown() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d -> Int64 in
            var w = Word(language: "es", lemma: "casa", pos: .noun); try w.insert(d); return w.id!
        }
        try await db.startLearning(wordID: id, now: now)
        var w = Word(language: "", lemma: "", pos: .noun)
        for _ in 0..<8 { w = try await db.recordReview(wordID: id, correct: true, now: now) }
        XCTAssertEqual(w.status, .finished)
        XCTAssertEqual(w.stage, .finished)
        XCTAssertNil(w.nextReview)

        try await db.markKnown(wordID: id)
        let known = try await db.writer.read { try Word.fetchOne($0, key: id)! }
        XCTAssertEqual(known.status, .known)
        XCTAssertNil(known.stage)
    }

    func testReviewRejectsNonLearningWord() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d -> Int64 in
            var w = Word(language: "es", lemma: "casa", pos: .noun); try w.insert(d); return w.id!
        }
        do {
            try await db.recordReview(wordID: id, correct: true)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? LangError, .notLearning) }
        do {
            try await db.recordReview(wordID: 999, correct: true)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? LangError, .notFound) }
    }
}
