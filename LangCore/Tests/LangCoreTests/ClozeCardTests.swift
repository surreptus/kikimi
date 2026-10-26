import GRDB
import XCTest
@testable import LangCore

final class ClozeCardTests: XCTestCase {
    private func card(lemma: String, surface: String, text: String, gloss: String?, reading: String? = nil,
                      language: String = "es") throws -> ReviewCard {
        let example = try ExampleLine(row: Row(["subtitle_id": 1, "surface": surface, "text": text, "start_time": 0.0,
                                                "end_time": 1.0, "video_id": 1, "video_title": "v", "media_path": "h/video.mov"]))
        let entries = gloss.map { [DictionaryEntry(id: 1, language: language, headword: lemma, reading: reading, gloss: $0)] } ?? []
        return ReviewCard(word: Word(id: 1, language: language, lemma: lemma, pos: .noun), entries: entries, example: example)
    }

    func testTheWordIsBlankedInTheSentenceAndTheHintIsTheMeaning() throws {
        let c = try XCTUnwrap(ClozeCard.make(
            from: try card(lemma: "casa", surface: "casa", text: "La casa es muy grande.", gloss: "1. (noun) house"), showsReading: false))
        XCTAssertEqual(c.prompt, "La ______ es muy grande.")
        XCTAssertEqual(c.answer, "casa")
        XCTAssertEqual(c.hint, "house", "no lemma when the sentence has the same form: it would give the answer away")
    }

    func testAnInflectedFormIsBlankedAndTheDictionaryFormIsInTheHint() throws {
        let c = try XCTUnwrap(ClozeCard.make(
            from: try card(lemma: "correr", surface: "Corremos", text: "Corremos a la casa.", gloss: "1. (verb) to run; to flow"), showsReading: false))
        XCTAssertEqual(c.prompt, "______ a la casa.")
        XCTAssertEqual(c.answer, "Corremos", "the form as it appears, capital included")
        XCTAssertEqual(c.hint, "correr · to run")
    }

    func testOnlyWholeWordsAreBlanked() throws {
        let c = try XCTUnwrap(ClozeCard.make(
            from: try card(lemma: "casa", surface: "casa", text: "Casablanca y la casa.", gloss: "house"), showsReading: false))
        XCTAssertEqual(c.prompt, "Casablanca y la ______.", "not the 'casa' inside Casablanca")
    }

    func testAnUnspacedLanguageBlanksTheWordAndHintsTheReading() throws {
        let c = try XCTUnwrap(ClozeCard.make(
            from: try card(lemma: "秋", surface: "秋", text: "日本の秋はきれいです。", gloss: "1. (noun) autumn; fall", reading: "あき", language: "ja"),
            showsReading: true))
        XCTAssertEqual(c.prompt, "日本の______はきれいです。")
        XCTAssertEqual(c.hint, "あき · autumn")
    }

    func testNoSentenceOrAWordNotFoundMeansNoClozeCard() throws {
        var noExample = try card(lemma: "casa", surface: "casa", text: "x", gloss: "house")
        noExample = ReviewCard(word: noExample.word, entries: noExample.entries, example: nil)
        XCTAssertNil(ClozeCard.make(from: noExample, showsReading: false))
        XCTAssertNil(ClozeCard.make(from: try card(lemma: "casa", surface: "perro", text: "La casa es grande.", gloss: "house"), showsReading: false))
    }

    func testTheGlossIsShortenedToTheFirstMeaning() {
        XCTAssertEqual(ClozeCard.shortGloss("1. (noun) house; home\n2. (noun) household"), "house")
        XCTAssertEqual(ClozeCard.shortGloss("to have"), "to have")
        XCTAssertEqual(ClozeCard.shortGloss("1. (noun) " + String(repeating: "x", count: 80))?.count, 60)
        XCTAssertNil(ClozeCard.shortGloss("1. (noun) "))
    }

    func testEachStyleSaysWhetherACardSuitsIt() throws {
        let withSentence = try card(lemma: "casa", surface: "casa", text: "La casa es grande.", gloss: "house")
        let wordNotInIt = try card(lemma: "casa", surface: "perro", text: "La casa es grande.", gloss: "house")
        let noSentence = ReviewCard(word: withSentence.word, entries: withSentence.entries, example: nil)
        XCTAssertTrue(ReviewStyle.meaning.suits(noSentence, showsReading: false), "the usual card needs nothing")
        XCTAssertTrue(ReviewStyle.cloze.suits(withSentence, showsReading: false))
        XCTAssertFalse(ReviewStyle.cloze.suits(wordNotInIt, showsReading: false))
        XCTAssertTrue(ReviewStyle.listening.suits(wordNotInIt, showsReading: false), "listening only needs the audio")
        XCTAssertFalse(ReviewStyle.listening.suits(noSentence, showsReading: false))
        XCTAssertEqual(ReviewStyle.allCases.map(\.rawValue), ["meaning", "cloze", "listening"])
    }

    func testTheStyleDefaultsToMeaningPerLanguageAndIsRemembered() {
        let defaults = UserDefaults(suiteName: "rs-\(UUID().uuidString)")!
        let preference = ReviewStylePreference(defaults: defaults)
        XCTAssertEqual(preference.style(for: SpanishProfile()), .meaning)
        preference.setStyle(.cloze, for: SpanishProfile())
        XCTAssertEqual(ReviewStylePreference(defaults: defaults).style(for: SpanishProfile()), .cloze)
        XCTAssertEqual(preference.style(for: JapaneseProfile()), .meaning, "another language is unaffected")
        preference.setStyle(.meaning, for: SpanishProfile())
        XCTAssertNil(defaults.string(forKey: "reviewStyle.es"))
    }
}
