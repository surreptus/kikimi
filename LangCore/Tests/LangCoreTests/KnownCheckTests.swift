import GRDB
import XCTest
@testable import LangCore

final class KnownCheckTests: XCTestCase {
    private func library() async throws -> LangDatabase {
        let db = try LangDatabase()
        try await db.writer.write { d in
            for (lemma, status) in [("casa", WordStatus.known), ("perro", .known), ("gato", .known), ("mesa", .learning),
                                    ("silla", .new), ("libro", .finished)] {
                var w = Word(language: "es", lemma: lemma, pos: .noun, status: status,
                             stage: status == .learning ? .stage3 : nil, nextReview: status == .learning ? Date.distantFuture : nil)
                try w.insert(d)
            }
            var other = Word(language: "ja", lemma: "犬", pos: .noun, status: .known); try other.insert(d)
        }
        return db
    }

    func testTheSampleIsOnlyKnownWordsOfThatLanguageAndNoMoreThanAsked() async throws {
        let db = try await library()
        let all = try await db.knownSample(language: "es", count: 10)
        let lemmas = try await db.writer.read { db in try all.map { try Word.fetchOne(db, key: $0)!.lemma } }
        XCTAssertEqual(Set(lemmas), ["casa", "perro", "gato"])
        let two = try await db.knownSample(language: "es", count: 2)
        XCTAssertEqual(two.count, 2)
    }

    func testAMissedWordGoesBackToLearningAndAKnownOneIsLeftAlone() async throws {
        let db = try await library()
        let session = try await ReviewSession(checkingKnown: db, language: "es", count: 3)
        let isCheck = await session.isKnownCheck
        XCTAssertTrue(isCheck)
        var missedLemma = ""
        var knownLemmas: [String] = []
        for step in 0..<3 {
            let card = try await session.currentCard()!
            if step == 0 { missedLemma = card.word.lemma; try await session.answer(correct: false) }
            else { knownLemmas.append(card.word.lemma); try await session.answer(correct: true) }
        }
        let remaining = await session.remaining
        let answered = await session.answered
        let correct = await session.correctFirstTry
        let returned = await session.returnedToLearning
        XCTAssertEqual([remaining, answered, correct, returned], [0, 3, 2, 1], "a missed word is not asked again")

        let missed = try await db.writer.read { try Word.filter(Column("lemma") == missedLemma).fetchOne($0)! }
        XCTAssertEqual(missed.status, .learning)
        XCTAssertEqual(missed.stage, .stage1, "starts again from the first stage")
        for lemma in knownLemmas {
            let word = try await db.writer.read { try Word.filter(Column("lemma") == lemma).fetchOne($0)! }
            XCTAssertEqual(word.status, .known)
        }
        let mesa = try await db.writer.read { try Word.filter(Column("lemma") == "mesa").fetchOne($0)! }
        XCTAssertEqual(mesa.stage, .stage3, "a word being learned is untouched")
    }
}
