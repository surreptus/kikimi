import XCTest
@testable import LangCore

final class TsumikiStemTests: XCTestCase {
    private func firstToken(_ text: String) -> Token { JapaneseProfile().tokenizer.tokens(in: text)[0] }

    func testEachFormMapsToItsStemPage() {
        let cases: [(String, TsumikiStem)] = [
            ("未然形", .mizenkei), ("未然ヌ接続", .mizenkei), ("未然レル接続", .mizenkei), ("未然ウ接続", .ishikei),
            ("連用形", .renyokei), ("連用ニ接続", .renyokei), ("連用タ接続", .taStem), ("連用テ接続", .teStem),
            ("仮定形", .kateikei), ("仮定縮約１", .kateikei), ("命令ｅ", .meireikei), ("命令ｒｏ", .meireikei),
        ]
        for (form, stem) in cases { XCTAssertEqual(TsumikiStem.stem(forInflection: form, pos: .verb), stem, form) }
    }

    func testTheDictionaryFormAndWordsThatDontInflectHaveNoLink() {
        XCTAssertNil(TsumikiStem.stem(forInflection: "基本形", pos: .verb))
        XCTAssertNil(TsumikiStem.stem(forInflection: "基本形", pos: .adjective))
        XCTAssertNil(TsumikiStem.stem(forInflection: nil, pos: .verb))
        XCTAssertNil(TsumikiStem.stem(forInflection: "未然形", pos: .noun), "only verbs and adjectives")
        XCTAssertNil(TsumikiStem.stem(forInflection: "不明", pos: .verb), "a form it doesn't know is left out, not guessed")
    }

    func testAnInflectedAdjectiveGoesToTheAdjectiveStem() {
        XCTAssertEqual(TsumikiStem.stem(forInflection: "連用テ接続", pos: .adjective), .gokan)
        XCTAssertEqual(TsumikiStem.stem(forInflection: "仮定形", pos: .adjective), .gokan)
    }

    func testPagesAreOnTheTsumikiSite() {
        XCTAssertEqual(TsumikiStem.mizenkei.url.absoluteString, "https://surreptus.github.io/tsumiki/reference/stems/mizenkei/")
        XCTAssertEqual(TsumikiStem.taStem.url.absoluteString, "https://surreptus.github.io/tsumiki/reference/stems/ta_stem/")
        XCTAssertEqual(Set(TsumikiStem.allCases.map(\.name)).count, 8, "every form has its own name")
    }

    func testRealJapaneseWordsAreMatchedToTheirForms() {
        // 食べさせられた: the verb stem is the ない-stem, since させ is what comes next.
        let eat = firstToken("食べさせられた")
        XCTAssertEqual(eat.lemma, "食べる")
        XCTAssertEqual(TsumikiStem.stem(for: eat), .mizenkei)
        // 行った: 行っ is the stem before た.
        XCTAssertEqual(TsumikiStem.stem(for: firstToken("行った")), .taStem)
        // 食べます: 食べ is the ます-stem.
        XCTAssertEqual(TsumikiStem.stem(for: firstToken("食べます")), .renyokei)
        // 食べれば: the ば-stem.
        XCTAssertEqual(TsumikiStem.stem(for: firstToken("食べれば")), .kateikei)
        // 高かった: an い-adjective, so the adjective stem. 食べる, the dictionary form, has none.
        XCTAssertEqual(TsumikiStem.stem(for: firstToken("高かった")), .gokan)
        XCTAssertNil(TsumikiStem.stem(for: firstToken("食べる")))
        XCTAssertNil(TsumikiStem.stem(for: firstToken("犬が")), "a noun")
    }
}
