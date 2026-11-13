import GRDB
import XCTest
@testable import LangCore

final class UndoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func library(status: WordStatus = .learning) async throws -> (LangDatabase, [Int64]) {
        let db = try LangDatabase()
        let ids: [Int64] = try await db.writer.write { d in
            try ["casa", "perro", "gato"].map { lemma in
                var w = Word(language: "es", lemma: lemma, pos: .noun, status: status,
                             stage: status == .learning ? .stage2 : nil,
                             nextReview: status == .learning ? Date(timeIntervalSince1970: 0) : nil)
                try w.insert(d)
                return w.id!
            }
        }
        return (db, ids)
    }

    private func word(_ db: LangDatabase, _ id: Int64) async throws -> Word {
        try await db.writer.read { try Word.fetchOne($0, key: id)! }
    }

    private func tally(_ db: LangDatabase, _ kind: ActivityKind) async throws -> Double {
        try await db.writer.read {
            try Double.fetchOne($0, sql: "SELECT COALESCE(SUM(amount), 0) FROM activity WHERE kind = ?", arguments: [kind.rawValue]) ?? 0
        }
    }

    // MARK: Review answers

    func testUndoingARightAnswerBringsBackStageNextReviewAndTally() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let id = try await session.currentCard()!.id
        let before = try await word(db, id)
        try await session.answer(correct: true, now: now)
        let answeredStage = try await word(db, id).stage
        XCTAssertNotEqual(answeredStage, before.stage)

        let undone = try await session.undoLast()
        XCTAssertTrue(undone)
        let back = try await word(db, id)
        XCTAssertEqual(back.stage, before.stage)
        XCTAssertEqual(back.nextReview, before.nextReview)
        let reviews = try await tally(db, .review), right = try await tally(db, .reviewCorrect)
        XCTAssertEqual([reviews, right], [0, 0])
        let sameCard = try await session.currentCard()?.id
        XCTAssertEqual(sameCard, id, "the same card is asked again")
        let remaining = await session.remaining, answered = await session.answered, first = await session.correctFirstTry
        XCTAssertEqual([remaining, answered, first], [3, 0, 0])
    }

    func testUndoingAMissTakesTheCardOffTheEndOfTheQueue() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let id = try await session.currentCard()!.id
        let before = try await word(db, id)
        try await session.answer(correct: false, now: now)
        let missedRemaining = await session.remaining
        XCTAssertEqual(missedRemaining, 3, "two others and the missed card at the back")

        let undone = try await session.undoLast()
        XCTAssertTrue(undone)
        let remaining = await session.remaining
        XCTAssertEqual(remaining, 3)
        let back = try await word(db, id)
        XCTAssertEqual(back.stage, before.stage)
        let reviews = try await tally(db, .review)
        XCTAssertEqual(reviews, 0)

        // The word is not marked as missed any more: answering it right now counts as a first try.
        try await session.answer(correct: true, now: now)
        let first = await session.correctFirstTry
        XCTAssertEqual(first, 1)
    }

    func testUndoingTheAnswerToAMissedCardAskedAgainLeavesTheStage() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let id = try await session.currentCard()!.id
        try await session.answer(correct: false, now: now)
        let afterMiss = try await word(db, id)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)
        let again = try await session.currentCard()!.id
        XCTAssertEqual(again, id)
        try await session.answer(correct: true, now: now)   // changes no stage, writes nothing

        let undone = try await session.undoLast()
        XCTAssertTrue(undone)
        let after = try await word(db, id)
        XCTAssertEqual(after.stage, afterMiss.stage, "the first answer's stage stays")
        let reviews = try await tally(db, .review)
        XCTAssertEqual(reviews, 3, "the three first answers stay in the tally")
        let sameCard = try await session.currentCard()?.id
        XCTAssertEqual(sameCard, id)
    }

    func testOnlyTheLatestAnswerCanBeUndoneAndOnlyOnce() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        try await session.answer(correct: true, now: now)
        try await session.answer(correct: true, now: now)
        let first = try await session.undoLast()
        let second = try await session.undoLast()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let reviews = try await tally(db, .review)
        XCTAssertEqual(reviews, 1, "the earlier answer stays")
    }

    func testAnAnswerIsNotUndoneOverProgressMadeAfterIt() async throws {
        let (db, _) = try await library()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let id = try await session.currentCard()!.id
        try await session.answer(correct: true, now: now)
        try await db.markKnown(wordID: id)   // you changed your mind about the word elsewhere

        let undone = try await session.undoLast()
        XCTAssertFalse(undone)
        let kept = try await word(db, id)
        XCTAssertEqual(kept.status, .known, "the newer change stays")
        let reviews = try await tally(db, .review)
        XCTAssertEqual(reviews, 1, "so does the tally")
    }

    func testPracticeAnswersHaveNothingToUndo() async throws {
        let (db, ids) = try await library()
        let session = ReviewSession(lessonQuiz: ids, database: db, language: "es")
        try await session.answer(correct: true, now: now)
        let can = await session.canUndo
        XCTAssertFalse(can)
    }

    // MARK: Status changes

    func testLearnCanBeUndoneWithItsTally() async throws {
        let (db, ids) = try await library(status: .new)
        let change = try await db.setStatus(.learning, ofWord: ids[0])
        let started = try await tally(db, .learn)
        XCTAssertEqual(started, 1)
        let n = try await db.undo(change)
        XCTAssertEqual(n, 1)
        let back = try await word(db, ids[0])
        XCTAssertEqual(back.status, .new)
        XCTAssertNil(back.stage)
        let after = try await tally(db, .learn)
        XCTAssertEqual(after, 0)
    }

    func testKnownOnALearningWordCanBeUndoneWithItsStage() async throws {
        let (db, ids) = try await library()
        let before = try await word(db, ids[0])
        let change = try await db.setStatus(.known, ofWord: ids[0])
        let known = try await word(db, ids[0])
        XCTAssertEqual(known.status, .known)
        XCTAssertNil(known.stage)
        try await db.undo(change)
        let back = try await word(db, ids[0])
        XCTAssertEqual(back.status, .learning)
        XCTAssertEqual(back.stage, before.stage)
        XCTAssertEqual(back.nextReview, before.nextReview)
        let tallyKnown = try await tally(db, .known)
        XCTAssertEqual(tallyKnown, 0)
    }

    func testIgnoreCanBeUndone() async throws {
        let (db, ids) = try await library(status: .new)
        let change = try await db.setStatus(.ignored, ofWord: ids[0])
        try await db.undo(change)
        let back = try await word(db, ids[0])
        XCTAssertEqual(back.status, .new)
    }

    func testUndoLeavesAWordYouHaveChangedSince() async throws {
        let (db, ids) = try await library(status: .new)
        let change = try await db.setStatus(.known, ofWord: ids[0])
        try await db.startLearning(wordID: ids[0])   // later, from the Words page
        let n = try await db.undo(change)
        XCTAssertEqual(n, 0)
        let kept = try await word(db, ids[0])
        XCTAssertEqual(kept.status, .learning)
    }

    func testAChangeThatMovedNothingIsEmpty() async throws {
        let (db, ids) = try await library()
        let change = try await db.setStatus(.learning, ofWord: ids[0])   // already learning
        XCTAssertTrue(change.isEmpty)
    }
}
