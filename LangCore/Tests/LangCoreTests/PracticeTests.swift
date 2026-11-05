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
