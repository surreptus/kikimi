import GRDB
import XCTest
@testable import LangCore

final class ActivityTests: XCTestCase {
    private let calendar = Calendar.current
    /// A Wednesday at noon, so "this week", "last week" and "yesterday" don't depend on when the test runs.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))! }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

    private func library() async throws -> (db: LangDatabase, words: [String: Int64], video: Int64) {
        let db = try LangDatabase()
        return try await db.writer.write { d in
            var v = Video(language: "es", title: "v", contentHash: "h", videoPath: "h/v.mov", duration: 600); try v.insert(d)
            var ids: [String: Int64] = [:]
            for (lemma, language) in [("casa", "es"), ("perro", "es"), ("gato", "es"), ("mesa", "es"), ("犬", "ja")] {
                var w = Word(language: language, lemma: lemma, pos: .noun); try w.insert(d); ids[lemma] = w.id!
            }
            return (db, ids, v.id!)
        }
    }

    private func count(_ db: LangDatabase, _ kind: ActivityKind) async throws -> Double {
        try await db.writer.read { try Double.fetchOne($0, sql: "SELECT COALESCE(SUM(amount), 0) FROM activity WHERE kind = ?", arguments: [kind.rawValue]) ?? 0 }
    }

    func testRecordingAddsToTheDaysTally() async throws {
        let (db, _, video) = try await library()
        try await db.record(.listen, subject: video, amount: 30, at: now)
        try await db.record(.listen, subject: video, amount: 12.5, at: now)
        try await db.record(.listen, subject: video, amount: 5, at: daysAgo(1))
        let rows = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT day, amount FROM activity ORDER BY day") }
        XCTAssertEqual(rows.count, 2, "one row per day")
        XCTAssertEqual(rows.map { $0["amount"] as Double }, [5, 42.5])
    }

    func testStartingLearningMarkingKnownAndReviewingAreTallied() async throws {
        let (db, w, _) = try await library()
        try await db.startLearning(wordID: w["casa"]!, now: now)
        try await db.startLearning(wordID: w["casa"]!, now: now)          // already learning: not a new start
        try await db.startLearning(wordIDs: [w["perro"]!, w["gato"]!, w["casa"]!], now: now)   // two new ones
        var learned = try await count(db, .learn)
        XCTAssertEqual(learned, 3)

        try await db.markKnown(wordID: w["mesa"]!)
        try await db.markKnown(wordID: w["mesa"]!)                          // already known
        try await db.markKnown(wordIDs: [w["mesa"]!, w["gato"]!])           // only gato is new to known
        var known = try await count(db, .known)
        XCTAssertEqual(known, 2)

        try await db.recordReview(wordID: w["casa"]!, correct: true, now: now)
        try await db.recordReview(wordID: w["perro"]!, correct: false, now: now)
        let reviews = try await count(db, .review), right = try await count(db, .reviewCorrect)
        XCTAssertEqual([reviews, right], [2, 1])
        learned = try await count(db, .learn); known = try await count(db, .known)
        XCTAssertEqual([learned, known], [3, 2], "reviewing starts and marks nothing")
    }

    func testTheStatsForOneLanguage() async throws {
        let (db, w, video) = try await library()
        // Started learning: 3 this week, 2 last week, 1 three weeks ago, 1 far outside the eight weeks shown.
        for _ in 0..<3 { try await db.record(.learn, subject: w["casa"]!, at: now) }
        for _ in 0..<2 { try await db.record(.learn, subject: w["perro"]!, at: daysAgo(7)) }
        try await db.record(.learn, subject: w["gato"]!, at: daysAgo(21))
        try await db.record(.learn, subject: w["mesa"]!, at: daysAgo(7 * 20))
        try await db.record(.learn, subject: w["犬"]!, at: now)                   // another language
        // Listening: 10 minutes today, 20 minutes two weeks ago.
        try await db.record(.listen, subject: video, amount: 600, at: now)
        try await db.record(.listen, subject: video, amount: 1200, at: daysAgo(14))
        // Reviews: 4 today (3 right), and 10 forty days ago (outside the 30 days).
        for i in 0..<4 {
            try await db.record(.review, subject: w["casa"]!, at: now)
            if i < 3 { try await db.record(.reviewCorrect, subject: w["casa"]!, at: now) }
        }
        try await db.record(.review, subject: w["casa"]!, amount: 10, at: daysAgo(40))
        // Lookups.
        for _ in 0..<3 { try await db.record(.lookup, subject: w["casa"]!, at: now) }
        try await db.record(.lookup, subject: w["perro"]!, at: daysAgo(2))
        try await db.record(.lookup, subject: w["犬"]!, at: now)

        let stats = try await db.learningStats(language: "es", now: now, calendar: calendar)
        XCTAssertEqual(stats.startedPerWeek.count, 8)
        XCTAssertEqual(Array(stats.startedPerWeek.suffix(4)), [1, 0, 2, 3], "three weeks ago, two, last week, this week")
        XCTAssertEqual(stats.startedPerWeek.reduce(0, +), 6, "the one 20 weeks ago is not shown, nor the Japanese word")
        XCTAssertEqual(stats.listenedThisWeek, 600)
        XCTAssertEqual(stats.listenedTotal, 1800)
        XCTAssertEqual([stats.reviews, stats.reviewsCorrect], [4, 3])
        XCTAssertEqual(stats.accuracy ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(stats.mostLookedUp, [.init(lemma: "casa", count: 3), .init(lemma: "perro", count: 1)])
        XCTAssertFalse(stats.isEmpty)

        let japanese = try await db.learningStats(language: "ja", now: now, calendar: calendar)
        XCTAssertEqual(japanese.startedPerWeek.reduce(0, +), 1)
        XCTAssertEqual(japanese.mostLookedUp.map(\.lemma), ["犬"])
    }

    func testNothingRecordedIsAnEmptyHistory() async throws {
        let (db, _, _) = try await library()
        let stats = try await db.learningStats(language: "es", now: now, calendar: calendar)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.accuracy)
    }
}
