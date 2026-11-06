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

    func testAnUnspacedLanguageBlanksTheWordAndHintsOnlyTheMeaning() throws {
        let c = try XCTUnwrap(ClozeCard.make(
            from: try card(lemma: "秋", surface: "秋", text: "日本の秋はきれいです。", gloss: "1. (noun) autumn; fall", reading: "あき", language: "ja"),
            showsReading: true))
        XCTAssertEqual(c.prompt, "日本の______はきれいです。")
        XCTAssertEqual(c.hint, "autumn", "the reading is the answer, so it is not on the front")
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
        XCTAssertTrue(ReviewStyle.dictation.suits(withSentence, showsReading: false, profile: SpanishProfile()), "a short line")
        XCTAssertFalse(ReviewStyle.dictation.suits(noSentence, showsReading: false, profile: SpanishProfile()))
        XCTAssertEqual(ReviewStyle.allCases.map(\.rawValue), ["meaning", "cloze", "listening", "dictation", "shadowing"])
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

final class ReviewPromptAnswerTests: XCTestCase {
    func testEveryStyleIsOneOfAPromptAndAnAnswer() {
        for style in ReviewStyle.allCases {
            XCTAssertEqual(ReviewStyle(prompt: style.prompt, answer: style.answer), style)
        }
    }

    func testOnlyASentenceCanBeTypedOrSpoken() {
        XCTAssertEqual(ReviewStyle(prompt: .sentence, answer: .type), .dictation)
        XCTAssertEqual(ReviewStyle(prompt: .sentence, answer: .speak), .shadowing)
        XCTAssertEqual(ReviewStyle(prompt: .sentence, answer: .check), .listening)
        XCTAssertNil(ReviewStyle(prompt: .word, answer: .type))
        XCTAssertNil(ReviewStyle(prompt: .cloze, answer: .speak))
    }
}

final class ShadowingStyleTests: XCTestCase {
    private func card(_ text: String?, end: Double) throws -> ReviewCard {
        let example = try text.map { try ExampleLine(row: Row(["subtitle_id": 1, "surface": "casa", "text": $0, "start_time": 0.0,
                                                               "end_time": end, "video_id": 1, "video_title": "v", "media_path": "h/video.mov"])) }
        return ReviewCard(word: Word(id: 1, language: "es", lemma: "casa", pos: .noun), entries: [], example: example)
    }

    func testShadowingNeedsAShortSentenceLikeTyping() throws {
        let es = SpanishProfile()
        XCTAssertTrue(ReviewStyle.shadowing.suits(try card("La casa es grande.", end: 2), showsReading: false, profile: es))
        XCTAssertFalse(ReviewStyle.shadowing.suits(
            try card("La casa es muy grande y tiene un jardín enorme con muchos árboles viejos.", end: 12), showsReading: false, profile: es),
            "too long to repeat")
        XCTAssertFalse(ReviewStyle.shadowing.suits(try card(nil, end: 1), showsReading: false, profile: es), "needs a sentence")
    }
}

final class SpanishLemmaFixTests: XCTestCase {
    private func lemmas(_ text: String) -> [String: String] {
        Dictionary(SpanishProfile().tokenizer.tokens(in: text).map { ($0.surface.lowercased(), $0.lemma) }, uniquingKeysWith: { a, _ in a })
    }

    func testPresentFormsOfPoderAreNotPodar() {
        // The tagger reads every present form of poder as podar, which would teach the wrong verb.
        let found = lemmas("Puedo ir. Tú puedes. Ella puede. Podemos hablar. Ellos pueden. Para que podáis hacer el quiz.")
        for form in ["puedo", "puedes", "puede", "podemos", "pueden", "podáis"] { XCTAssertEqual(found[form], "poder", form) }
    }

    func testOtherCommonVerbsAreFixedToo() {
        let found = lemmas("Él sale. Lo siento. Que venga. Creo que sí.")
        XCTAssertEqual(found["sale"], "salir")
        XCTAssertEqual(found["siento"], "sentir")
        XCTAssertEqual(found["venga"], "venir")
        XCTAssertEqual(found["creo"], "creer")
    }

    func testTheRealVerbPodarKeepsItsOwnForms() {
        XCTAssertEqual(lemmas("Él poda las rosas.")["poda"], "podar", "left to the tagger")
        XCTAssertEqual(lemmas("Hay que podar el árbol.")["podar"], "podar")
    }
}
