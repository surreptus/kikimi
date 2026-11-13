import GRDB
import XCTest
@testable import LangCore

final class ReviewSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func library() async throws -> (LangDatabase, [Int64]) {
        let db = try LangDatabase()
        let ids: [Int64] = try await db.writer.write { d in
            try ["casa", "perro", "gato"].map { lemma in
                var w = Word(language: "es", lemma: lemma, pos: .noun, status: .learning,
                             stage: .stage2, nextReview: Date(timeIntervalSince1970: 0))
                try w.insert(d)
                return w.id!
            }
        }
        return (db, ids)
    }

    func testAWordMarkedKnownMidSessionIsSkippedAndTheSessionContinues() async throws {
        let (db, ids) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let first = try await session.currentCard()!.id
        try await db.markKnown(wordID: first)
        try await session.answer(correct: true, now: now)   // must not throw
        var remaining = await session.remaining
        var answered = await session.answered
        var correct = await session.correctFirstTry
        XCTAssertEqual([remaining, answered, correct], [ids.count - 1, 0, 0], "not counted as right or missed")
        let next = try await session.currentCard()
        XCTAssertNotEqual(next?.id, first)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)
        remaining = await session.remaining
        answered = await session.answered
        correct = await session.correctFirstTry
        XCTAssertEqual([remaining, answered, correct], [0, 2, 2])
        let word = try await db.writer.read { try Word.fetchOne($0, key: first)! }
        XCTAssertEqual(word.status, .known, "the skipped word is left as the learner set it")
    }

    func testAMissedWordMarkedKnownIsNotAskedAgain() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let first = try await session.currentCard()!.id
        try await session.answer(correct: false, now: now)   // goes to the back of the queue
        try await db.markKnown(wordID: first)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)    // the missed word, now known: no stage change, no error
        let remaining = await session.remaining
        XCTAssertEqual(remaining, 0)
    }

    func testTheLastCardMarkedKnownFinishesTheSessionNormally() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)
        let last = try await session.currentCard()!.id
        try await db.markKnown(wordID: last)
        try await session.answer(correct: false, now: now)   // skipped: not re-queued even though answered wrong
        let remaining = await session.remaining
        let answered = await session.answered
        let correct = await session.correctFirstTry
        let card = try await session.currentCard()
        XCTAssertEqual([remaining, answered, correct], [0, 2, 2])
        XCTAssertNil(card)
    }

    func testAnAnswerToAWordStillLearningIsUnaffected() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let first = try await session.currentCard()!.id
        try await session.answer(correct: true, now: now)
        let word = try await db.writer.read { try Word.fetchOne($0, key: first)! }
        XCTAssertEqual(word.stage, .stage3)
        let answered = await session.answered
        let correct = await session.correctFirstTry
        XCTAssertEqual([answered, correct], [1, 1])
    }
}
