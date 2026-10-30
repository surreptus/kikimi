import GRDB
import XCTest
@testable import LangCore

final class HomographHintTests: XCTestCase {
    /// 秋 has two entries, and the wrong one (とき) comes first in the file.
    func testTheHintUsesTheReadingTheTokenizerSawWhenAnEntryMatches() async throws {
        let env = try makeEnvironment(entries: [("秋", "とき", "time; hour; moment"), ("秋", "あき", "autumn; fall")])
        defer { try? FileManager.default.removeItem(at: env.root) }
        let aki = Token(surface: "秋", lemma: "秋", pos: .noun, reading: "あき")
        let hint = await env.hint(for: aki, language: "ja")
        XCTAssertEqual(hint?.reading, "あき")
        XCTAssertEqual(hint?.gloss, "autumn; fall", "and the meaning that goes with that reading")
    }

    func testTheHintListsTheOtherReadingsToo() async throws {
        let env = try makeEnvironment(entries: [("月", "つき", "moon"), ("月", "がつ", "month"), ("月", "げつ", "Monday"), ("付き", "つき", "attached")])
        defer { try? FileManager.default.removeItem(at: env.root) }
        let gatsu = Token(surface: "月", lemma: "月", pos: .noun, reading: "がつ")
        let hint = await env.hint(for: gatsu, language: "ja")
        XCTAssertEqual(hint?.reading, "がつ")
        XCTAssertEqual(hint?.otherReadings, ["つき", "げつ"], "the others, commoner first, without the one shown or other spellings' readings")
    }

    func testReadingsAreDistinctLimitedAndLeadWithTheGivenOne() {
        let entries = ["a", "b", "a", "c", "d", "e"].map { DictionaryEntry(language: "ja", headword: "x", reading: $0, gloss: "") }
            + [DictionaryEntry(language: "ja", headword: "y", reading: "z", gloss: ""), DictionaryEntry(language: "es", headword: "x", gloss: "")]
        XCTAssertEqual(entries.readings(of: "x"), ["a", "b", "c", "d"])
        XCTAssertEqual(entries.readings(of: "x", first: "c"), ["c", "a", "b", "d"])
        XCTAssertEqual(entries.readings(of: "q"), [])
    }

    func testWithNoMatchingReadingItFallsBackToTheFirstEntry() async throws {
        let env = try makeEnvironment(entries: [("秋", "とき", "time"), ("秋", "あき", "autumn")])
        defer { try? FileManager.default.removeItem(at: env.root) }
        let noReading = Token(surface: "秋", lemma: "秋", pos: .noun, reading: nil)
        let none = await env.hint(for: noReading, language: "ja")
        XCTAssertEqual(none?.reading, "とき", "nothing to go on, so the first entry")
        let other = Token(surface: "秋", lemma: "秋", pos: .noun, reading: "しゅう")
        let unmatched = await env.hint(for: other, language: "ja")
        XCTAssertEqual(unmatched?.reading, "とき")
    }

    private func makeEnvironment(entries: [TestDictionaries.Entry]) throws -> LangEnvironment {
        try LangEnvironment(
            root: FileManager.default.temporaryDirectory.appending(path: "hh-\(UUID().uuidString)"),
            defaults: UserDefaults(suiteName: "hh-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([])),
            dictionaries: TestDictionaries.store(["ja": entries, "es": [("casa", nil, "house")]]))
    }
}

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
        XCTAssertEqual(known, WordHint(wordID: knownID, lemma: "友達", pos: .noun, reading: "ともだち", gloss: "friend; companion", status: .known, stage: nil))

        // A word that isn't in the dictionary or your list still gets a hint, with whatever the tokenizer knew.
        let unknown = await env.hint(for: Token(surface: "走り", lemma: "走る", pos: .verb, reading: "はしり"), language: "ja")
        XCTAssertEqual(unknown?.reading, "はしり")
        XCTAssertNil(unknown?.gloss)
        XCTAssertNil(unknown?.status)
        XCTAssertNil(unknown?.wordID)
    }
}
