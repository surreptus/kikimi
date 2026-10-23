import GRDB
import XCTest
@testable import LangCore

final class LineSegmentsTests: XCTestCase {
    private func rejoin(_ segments: [LineSegment]) -> String { segments.map(\.text).joined() }

    func testSpanishLineKeepsEveryCharacterAndMarksWords() {
        let text = "¿Qué tal, amigos? La casa es grande."
        let segments = SpanishProfile().lineSegments(in: text)
        XCTAssertEqual(rejoin(segments), text, "nothing is lost: spaces, punctuation and accents stay")
        let words = segments.compactMap(\.token).map(\.surface)
        XCTAssertTrue(words.contains("casa"))
        XCTAssertTrue(words.contains("grande"))
        XCTAssertEqual(segments.filter { $0.token == nil }.contains { $0.text.contains("¿") }, true, "punctuation is a plain segment")
        XCTAssertTrue(segments.enumerated().allSatisfy { $0.offset == $0.element.id })
    }

    func testJapaneseLineKeepsEveryCharacterAndGivesFurigana() {
        let text = "昨日は友達と行きました。"
        let segments = JapaneseProfile().lineSegments(in: text)
        XCTAssertEqual(rejoin(segments), text)

        let byText = Dictionary(segments.compactMap { s in s.token.map { (s.text, $0) } }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byText["友達"]?.reading, "ともだち")
        XCTAssertEqual(byText["昨日"]?.reading, "きのう")
        XCTAssertEqual(byText["行き"]?.reading, "いき", "the reading of the inflected form, not the dictionary form")
        XCTAssertEqual(byText["行き"]?.lemma, "行く")
        XCTAssertNil(byText["は"]?.reading, "kana needs no furigana")
        XCTAssertNil(byText["まし"]?.reading)
    }

    func testKatakanaWordsGetNoFurigana() {
        let segments = JapaneseProfile().lineSegments(in: "コーヒーを飲みます。")
        XCTAssertEqual(rejoin(segments), "コーヒーを飲みます。")
        XCTAssertNil(segments.first { $0.text == "コーヒー" }?.token?.reading)
        XCTAssertEqual(segments.first { $0.text == "飲み" }?.token?.reading, "のみ")
    }

    func testEdgeCases() {
        XCTAssertTrue(SpanishProfile().lineSegments(in: "").isEmpty)
        XCTAssertEqual(rejoin(SpanishProfile().lineSegments(in: "...")), "...")
        XCTAssertEqual(rejoin(JapaneseProfile().lineSegments(in: "  ")), "  ")
        let mixed = "Hola 世界 123 ok"
        XCTAssertEqual(rejoin(SpanishProfile().lineSegments(in: mixed)), mixed)
    }

    func testKatakanaToHiragana() {
        XCTAssertEqual(JapaneseProfile.hiragana(fromKatakana: "トモダチ"), "ともだち")
        XCTAssertEqual(JapaneseProfile.hiragana(fromKatakana: "コーヒー"), "こーひー", "the long vowel mark stays")
        XCTAssertEqual(JapaneseProfile.hiragana(fromKatakana: "ともだち"), "ともだち")
        XCTAssertTrue(JapaneseProfile.containsKanji("行き"))
        XCTAssertFalse(JapaneseProfile.containsKanji("ゆっくり"))
    }
}

final class WordHintTests: XCTestCase {
    func testShortGlossDropsNumberingAndPartOfSpeech() {
        func short(_ gloss: String) -> String { DictionaryEntry(language: "es", headword: "x", gloss: gloss).shortGloss }
        XCTAssertEqual(short("1. (noun) house; home\n2. household"), "house; home")
        XCTAssertEqual(short("1. (v1, vt) to eat\n2. to live on"), "to eat")
        XCTAssertEqual(short("to be"), "to be", "plain text is untouched")
        XCTAssertEqual(short(""), "")
    }

    func testHintCombinesDictionaryEntryAndYourWordStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let env = try LangEnvironment(
            root: root, defaults: UserDefaults(suiteName: "hint-\(UUID().uuidString)")!,
            dictionaries: TestDictionaries.store(["ja": [("友達", "ともだち", "1. (n) friend; companion")]]))
        var knownID: Int64 = 0
        try await env.database.writer.write { db in
            var word = Word(language: "ja", lemma: "友達", pos: .noun, status: .known)
            try word.insert(db)
            knownID = word.id!
        }
        let known = await env.hint(for: Token(surface: "友達", lemma: "友達", pos: .noun, reading: "ともだち"), language: "ja")
        XCTAssertEqual(known, WordHint(wordID: knownID, lemma: "友達", pos: .noun, reading: "ともだち", gloss: "friend; companion", status: .known))

        // A word that isn't in the dictionary or your list still gets a hint, with whatever the tokenizer knew.
        let unknown = await env.hint(for: Token(surface: "走り", lemma: "走る", pos: .verb, reading: "はしり"), language: "ja")
        XCTAssertEqual(unknown?.reading, "はしり")
        XCTAssertNil(unknown?.gloss)
        XCTAssertNil(unknown?.status)
        XCTAssertNil(unknown?.wordID)
    }
}
