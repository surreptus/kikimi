import GRDB
import XCTest
@testable import LangCore

final class DictationTests: XCTestCase {
    private let es = SpanishProfile(), ja = JapaneseProfile()

    private func line(_ text: String, seconds: Double = 3) -> ExampleLine {
        ExampleLine(id: 1, surface: "x", text: text, startTime: 10, endTime: 10 + seconds, videoID: 1, videoTitle: "v", mediaPath: "a")
    }

    func testPiecesAreWordsOrCharactersAndPunctuationIsNotAPiece() {
        XCTAssertEqual(es.dictationUnits(in: "¿Dónde está la casa?"), ["¿Dónde", "está", "la", "casa?"])
        XCTAssertEqual(es.dictationUnits(in: "— ... !"), [], "punctuation alone is nothing to type")
        XCTAssertEqual(ja.dictationUnits(in: "今日は横浜に来ました。").count, 10)
    }

    func testAnExactCopyIgnoresCaseWidthAndPunctuationButNotAccents() {
        XCTAssertTrue(DictationCheck.compare(typed: "donde esta la casa", line: "¿Dónde está la casa?", profile: es).isExact == false,
                      "accents are part of the spelling")
        XCTAssertTrue(DictationCheck.compare(typed: "dónde está la CASA", line: "¿Dónde está la casa?", profile: es).isExact)
        XCTAssertTrue(DictationCheck.compare(typed: "ＡＢＣ　ｄｅｆ", line: "abc def", profile: es).isExact, "full-width letters match")
    }

    func testMissedAndExtraPiecesAreMarkedInPlace() {
        let missed = DictationCheck.compare(typed: "la casa grande", line: "La casa es grande", profile: es)
        XCTAssertEqual(missed.pieces.map(\.kind), [.same, .same, .missed, .same])
        XCTAssertEqual(missed.pieces[2].text, "es")
        XCTAssertEqual([missed.correct, missed.total], [3, 4])
        let extra = DictationCheck.compare(typed: "la casa muy grande", line: "la casa grande", profile: es)
        XCTAssertEqual(extra.pieces.map(\.kind), [.same, .same, .extra, .same])
        XCTAssertEqual([extra.correct, extra.total], [3, 3])
        XCTAssertFalse(extra.isExact, "something extra is not an exact copy")
    }

    func testNothingTypedMissesEverything() {
        let none = DictationCheck.compare(typed: "  ", line: "la casa", profile: es)
        XCTAssertEqual(none.pieces.map(\.kind), [.missed, .missed])
        XCTAssertEqual(none.correct, 0)
    }

    func testJapaneseIsComparedACharacterAtATime() {
        let check = DictationCheck.compare(typed: "今日は氷河浜に来ました", line: "今日は横浜に来ました。", profile: ja)
        XCTAssertEqual([check.correct, check.total], [9, 10], "only 横 was missed")
        XCTAssertEqual(check.pieces.filter { $0.kind == .missed }.map(\.text), ["横"])
        XCTAssertEqual(check.pieces.filter { $0.kind == .extra }.map(\.text).joined(), "氷河")
    }

    func testOnlyShortLinesAreOfferedForTyping() {
        XCTAssertTrue(es.suitsDictation(line("La casa es grande y muy bonita.", seconds: 3)))
        XCTAssertFalse(es.suitsDictation(line("La casa es grande y muy bonita.", seconds: 7)), "too long on the clock")
        XCTAssertFalse(es.suitsDictation(line("uno dos tres cuatro cinco seis siete ocho nueve diez once")), "eleven words")
        XCTAssertTrue(es.suitsDictation(line("uno dos tres cuatro cinco seis siete ocho nueve diez")), "ten words")
        XCTAssertFalse(es.suitsDictation(line("...")), "nothing to type")
        XCTAssertTrue(ja.suitsDictation(line(String(repeating: "あ", count: 25))))
        XCTAssertFalse(ja.suitsDictation(line(String(repeating: "あ", count: 26))), "26 characters")
    }

    func testTheDictationStyleNeedsASentenceThatIsShortEnough() {
        let word = Word(id: 1, language: "es", lemma: "casa", pos: .noun)
        let short = ReviewCard(word: word, entries: [], example: line("La casa es grande."))
        let long = ReviewCard(word: word, entries: [], example: line("La casa es grande.", seconds: 12))
        let none = ReviewCard(word: word, entries: [], example: nil)
        XCTAssertTrue(ReviewStyle.dictation.suits(short, showsReading: false, profile: es))
        XCTAssertFalse(ReviewStyle.dictation.suits(long, showsReading: false, profile: es))
        XCTAssertFalse(ReviewStyle.dictation.suits(none, showsReading: false, profile: es))
    }

    func testASessionPrefersAShortLineForAWordThatHasOne() async throws {
        let db = try LangDatabase()
        let video = Video(language: "es", title: "v", contentHash: "d", videoPath: "d/v", duration: 40)
        let longText = "La casa de mi abuela es muy grande y tiene un jardín enorme con muchas flores de todos los colores"
        _ = try await db.saveImport(video: video, subtitles: [
            (segment: TranscriptSegment(start: 0, end: 12, text: longText), tokens: es.contentWords(in: longText)),
            (segment: TranscriptSegment(start: 20, end: 22, text: "Mi casa es pequeña."), tokens: es.contentWords(in: "Mi casa es pequeña.")),
        ])
        let casa = try await db.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        let now = Date(timeIntervalSince1970: 1_000)
        try await db.startLearning(wordID: casa, now: now)
        for _ in 0..<5 {
            let session = try await ReviewSession(database: db, language: "es", preferring: { SpanishProfile().suitsDictation($0) }, now: now.addingTimeInterval(100_000))
            let card = try await session.currentCard()
            XCTAssertEqual(card?.example?.text, "Mi casa es pequeña.")
        }
        let any = try await ReviewSession(database: db, language: "es", now: now.addingTimeInterval(100_000))
        let anyCard = try await any.currentCard()
        XCTAssertNotNil(anyCard?.example, "with no preference, any line will do")
    }
}
