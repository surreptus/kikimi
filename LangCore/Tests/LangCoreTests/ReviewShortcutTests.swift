import XCTest
@testable import LangCore

final class ReviewShortcutTests: XCTestCase {
    private func keys(revealed: Bool = true, typing: Bool = false, sentence: Bool = true, translate: Bool = true, voice: Bool = true, furigana: Bool = false) -> [String] {
        ReviewShortcut.available(revealed: revealed, typing: typing, hasSentence: sentence, canTranslate: translate, voiceAvailable: voice, hasFurigana: furigana).map(\.key)
    }

    func testNothingIsOfferedBeforeTheAnswerExceptOnATypedCard() {
        XCTAssertEqual(keys(revealed: false), [])
        XCTAssertEqual(keys(revealed: false, typing: true), ["Return", "⌘R"])
    }

    func testAfterTheAnswerEverythingIsOfferedWhenItCanBeDone() {
        XCTAssertEqual(keys(), ["W", "I", "E", "T"])
    }

    func testFuriganaIsOfferedOnlyForAJapaneseCardWithASentence() {
        XCTAssertEqual(keys(furigana: true), ["W", "I", "F", "E", "T"])
        XCTAssertEqual(keys(sentence: false, furigana: true), ["W", "I"])
    }

    func testEachKeyIsLeftOutWhenItCannotWork() {
        XCTAssertEqual(keys(voice: false), ["I", "E", "T"], "no installed voice, no Say word")
        XCTAssertEqual(keys(translate: false), ["W", "I", "E"], "a Mac that cannot translate offers no T")
        XCTAssertEqual(keys(sentence: false), ["W", "I"], "a card with no sentence has nothing to edit or translate")
    }

    func testOnlyTheKeysWithNoButtonOfTheirOwnAreBoundAsBareLetters() {
        XCTAssertEqual(ReviewShortcut.allCases.compactMap(\.letter), ["w", "i", "f", "e", "t"])
        XCTAssertNil(ReviewShortcut.check.letter)
        XCTAssertNil(ReviewShortcut.playAgain.letter)
    }

    func testATextFieldKeepsEveryBareLetterFromTheMenu() {
        let all = ReviewShortcut.allCases
        XCTAssertEqual(ReviewShortcut.menuKeys(offered: all, textFieldFocused: true), [.check, .playAgain])
        XCTAssertEqual(ReviewShortcut.menuKeys(offered: all, textFieldFocused: false), all)
    }
}
