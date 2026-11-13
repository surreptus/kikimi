import GRDB
import XCTest
@testable import LangCore

private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class SRSVariationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testJitterMovesAnIntervalByAtMostTheVariation() {
        let base = SRS.interval(for: .stage5)!
        XCTAssertEqual(SRS.interval(for: .stage5, jitter: 1)!, base * 1.1, accuracy: 0.001)
        XCTAssertEqual(SRS.interval(for: .stage5, jitter: -1)!, base * 0.9, accuracy: 0.001)
        XCTAssertEqual(SRS.interval(for: .stage5, jitter: 0)!, base)
        XCTAssertEqual(SRS.interval(for: .stage5, jitter: 50)!, base * 1.1, accuracy: 0.001, "out-of-range jitter is clamped")
    }

    func testNoIntervalIsShorterThanTheFirstWait() {
        let floor = SRS.intervals[0]
        for stage in SRSStage.allCases.dropLast() {
            XCTAssertGreaterThanOrEqual(SRS.interval(for: stage, jitter: -1)!, floor)
        }
        XCTAssertEqual(SRS.interval(for: .stage1, jitter: -1)!, floor, "a stage-1 card is never asked early")
        XCTAssertNil(SRS.interval(for: .finished, jitter: 1))
    }

    func testAnswerUsesTheJitter() {
        let r = SRS.answer(stage: .stage4, correct: true, now: now, jitter: -1)
        XCTAssertEqual(r.nextReview, now.addingTimeInterval(7 * 86400 * 0.9))
    }

    func testRandomJitterIsInRangeAndRepeatableForOneSeed() {
        var a = Seeded(state: 7), b = Seeded(state: 7)
        let first = (0..<200).map { _ in SRS.randomJitter(using: &a) }
        let second = (0..<200).map { _ in SRS.randomJitter(using: &b) }
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.allSatisfy { (-1...1).contains($0) })
        XCTAssertGreaterThan(Set(first).count, 150, "the values differ, so a pile spreads out")
    }

    func testRecordReviewSpreadsWordsAnsweredTogether() async throws {
        let db = try LangDatabase()
        let start = now
        let ids = try await db.writer.write { d in
            try (0..<20).map { i -> Int64 in
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun, status: .learning, stage: .stage4, nextReview: start)
                try w.insert(d); return w.id!
            }
        }
        var generator = Seeded(state: 1)
        var due = Set<Date>()
        for id in ids {
            let w = try await db.recordReview(wordID: id, correct: true, now: now, jitter: SRS.randomJitter(using: &generator))
            let wait = w.nextReview!.timeIntervalSince(now)
            XCTAssertTrue((7 * 86400 * 0.9...7 * 86400 * 1.1).contains(wait))
            due.insert(w.nextReview!)
        }
        XCTAssertGreaterThan(due.count, 15)
    }
}

final class ReviewLimitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func pile(_ count: Int) async throws -> LangDatabase {
        let db = try LangDatabase()
        try await db.writer.write { d in
            for i in 0..<count {
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun, status: .learning, stage: .stage1,
                             nextReview: Date(timeIntervalSince1970: Double(i)))
                try w.insert(d)
            }
        }
        return db
    }

    func testASessionAsksOnlyTheLimitAndTheOldestFirst() async throws {
        let db = try await pile(8)
        let session = try await ReviewSession(database: db, language: "es", now: now, limit: 5)
        let remaining = await session.remaining
        XCTAssertEqual(remaining, 5)
        let first = try await session.currentCard()
        XCTAssertEqual(first?.word.lemma, "w0")
    }

    func testTheRestStayDueAndCountTruthfully() async throws {
        let db = try await pile(8)
        let session = try await ReviewSession(database: db, language: "es", now: now, limit: 5)
        for _ in 0..<5 { try await session.answer(correct: true, now: now) }
        let due = try await db.dueCount(language: "es", now: now)
        XCTAssertEqual(due, 3, "the count is of all that are due, so it falls as sessions are done")
        let next = try await ReviewSession(database: db, language: "es", now: now, limit: 5)
        let remaining = await next.remaining
        XCTAssertEqual(remaining, 3)
    }

    func testTheDefaultLimitApplies() async throws {
        let db = try await pile(ReviewSession.sizeLimit + 10)
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let remaining = await session.remaining
        XCTAssertEqual(remaining, ReviewSession.sizeLimit)
    }
}

final class NewWordRoomTests: XCTestCase {
    private func library(startedToday: Int) async throws -> LangDatabase {
        let db = try LangDatabase()
        let ids = try await db.writer.write { d in
            try (0..<4).map { i -> Int64 in
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun); try w.insert(d); return w.id!
            }
        }
        try await db.startLearning(wordIDs: Array(ids.prefix(startedToday)))
        return db
    }

    func testRoomIsTheAllowanceLeftAfterWhatWasStartedToday() async throws {
        let db = try await library(startedToday: 3)
        let room = try await db.newWordRoom(language: "es", perDay: 5)
        XCTAssertEqual(room, 2)
    }

    func testRoomIsNeverBelowZero() async throws {
        let db = try await library(startedToday: 3)
        let room = try await db.newWordRoom(language: "es", perDay: 2)
        XCTAssertEqual(room, 0)
    }

    func testNoLimitWhenLessonsAreOff() async throws {
        let db = try await library(startedToday: 3)
        let room = try await db.newWordRoom(language: "es", perDay: 0)
        XCTAssertNil(room)
    }

    func testAnotherLanguageHasItsOwnAllowance() async throws {
        let db = try await library(startedToday: 3)
        let room = try await db.newWordRoom(language: "ja", perDay: 5)
        XCTAssertEqual(room, 5)
    }
}
