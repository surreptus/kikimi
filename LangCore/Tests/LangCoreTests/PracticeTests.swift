import GRDB
import XCTest
@testable import LangCore

final class PracticeTests: XCTestCase {
    private func library() async throws -> LangDatabase {
        let db = try LangDatabase()
        let now = Date()
        try await db.writer.write { d in
            for (lemma, status, due) in [("casa", WordStatus.learning, now.addingTimeInterval(-60)),
                                         ("perro", .learning, now.addingTimeInterval(7200)),
                                         ("gato", .learning, now.addingTimeInterval(3600)),
                                         ("libro", .finished, nil), ("mesa", .known, nil)] {
                var w = Word(language: "es", lemma: lemma, pos: .noun, status: status,
                             stage: status == .learning ? .stage3 : nil, nextReview: due)
                try w.insert(d)
            }
            var other = Word(language: "ja", lemma: "犬", pos: .noun, status: .finished); try other.insert(d)
        }
        return db
    }

    private func snapshot(_ db: LangDatabase) async throws -> [String] {
        try await db.writer.read { db in
            try Word.order(Column("id")).fetchAll(db).map {
                "\($0.lemma) \($0.status) \(String(describing: $0.stage)) \($0.nextReview?.timeIntervalSince1970 ?? 0)"
            }
        }
    }

    func testReviewAheadIsTheLearningWordsNotYetDueSoonestFirst() async throws {
        let db = try await library()
        let ids = try await db.practiceSample(.ahead, language: "es", count: 10)
        let lemmas = try await db.writer.read { db in try ids.map { try Word.fetchOne(db, key: $0)!.lemma } }
        XCTAssertEqual(lemmas, ["gato", "perro"], "casa is already due, so it is a review and not extra study")
    }

    func testPracticeFinishedIsOnlyFinishedWordsOfThatLanguage() async throws {
        let db = try await library()
        let ids = try await db.practiceSample(.finished, language: "es", count: 10)
        let lemmas = try await db.writer.read { db in try ids.map { try Word.fetchOne(db, key: $0)!.lemma } }
        XCTAssertEqual(lemmas, ["libro"])
    }

    func testPracticeChangesNothingEvenWhenMissed() async throws {
        let db = try await library()
        let before = try await snapshot(db)
        let session = try await ReviewSession(practising: .ahead, database: db, language: "es")
        let isPractice = await session.isPractice
        XCTAssertTrue(isPractice)
        _ = try await session.currentCard()
        try await session.answer(correct: false)
        _ = try await session.currentCard()
        try await session.answer(correct: true)
        let remaining = await session.remaining
        let answered = await session.answered
        let correct = await session.correctFirstTry
        XCTAssertEqual([remaining, answered, correct], [0, 2, 1], "a miss is not asked again")
        let after = try await snapshot(db)
        XCTAssertEqual(before, after, "no stage, status or date moved")
    }
}

final class LessonQuizTests: XCTestCase {
    func testTheDayIsTaughtInBatchesOfFive() {
        let lessons = DailyLessons(wordIDs: Array(1...12), perDay: 15)
        XCTAssertEqual(lessons.batches.map(\.count), [5, 5, 2])
        XCTAssertTrue(DailyLessons().batches.isEmpty)
    }

    func testAWordTaughtInALessonIsDueAfterItsFirstInterval() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d -> Int64 in
            var w = Word(language: "es", lemma: "casa", pos: .noun); try w.insert(d); return w.id!
        }
        let now = Date()
        try await db.startLearning(wordIDs: [id], now: now, firstReviewAfter: SRS.intervals[0])
        let word = try await db.word(id: id)
        XCTAssertEqual(word?.nextReview?.timeIntervalSince(now) ?? 0, SRS.intervals[0], accuracy: 0.01)
        let due = try await db.dueCount(language: "es", now: now)
        XCTAssertEqual(due, 0, "the lesson's own quiz is the first look, so it is not also a review")
    }

    func testAMissedWordInTheQuizIsAskedAgainAndNothingMoves() async throws {
        let db = try LangDatabase()
        let ids = try await db.writer.write { d -> [Int64] in
            try ["casa", "perro"].map { lemma in
                var w = Word(language: "es", lemma: lemma, pos: .noun, status: .learning, stage: .stage1,
                             nextReview: Date().addingTimeInterval(14_400)); try w.insert(d); return w.id!
            }
        }
        let session = ReviewSession(lessonQuiz: ids, database: db, language: "es")
        _ = try await session.currentCard(); try await session.answer(correct: false)   // casa missed
        _ = try await session.currentCard(); try await session.answer(correct: true)    // perro right
        var remaining = await session.remaining
        XCTAssertEqual(remaining, 1, "casa comes back")
        _ = try await session.currentCard(); try await session.answer(correct: true)
        remaining = await session.remaining
        let correct = await session.correctFirstTry
        XCTAssertEqual([remaining, correct], [0, 1], "only perro was right the first time")
        let stages = try await db.writer.read { try Word.fetchAll($0).map(\.stage) }
        XCTAssertEqual(stages, [.stage1, .stage1])
    }
}
