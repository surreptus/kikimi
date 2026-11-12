import XCTest
@testable import LangCore

final class ReviewShortcutTests: XCTestCase {
    private func keys(revealed: Bool = true, typing: Bool = false, sentence: Bool = true, translate: Bool = true, voice: Bool = true) -> [String] {
        ReviewShortcut.available(revealed: revealed, typing: typing, hasSentence: sentence, canTranslate: translate, voiceAvailable: voice).map(\.key)
    }

    func testNothingIsOfferedBeforeTheAnswerExceptOnATypedCard() {
        XCTAssertEqual(keys(revealed: false), [])
        XCTAssertEqual(keys(revealed: false, typing: true), ["Return", "⌘R"])
    }

    func testAfterTheAnswerEverythingIsOfferedWhenItCanBeDone() {
        XCTAssertEqual(keys(), ["W", "I", "E", "T"])
    }

    func testEachKeyIsLeftOutWhenItCannotWork() {
        XCTAssertEqual(keys(voice: false), ["I", "E", "T"], "no installed voice, no Say word")
        XCTAssertEqual(keys(translate: false), ["W", "I", "E"], "a Mac that cannot translate offers no T")
        XCTAssertEqual(keys(sentence: false), ["W", "I"], "a card with no sentence has nothing to edit or translate")
    }

    func testOnlyTheKeysWithNoButtonOfTheirOwnAreBoundAsBareLetters() {
        XCTAssertEqual(ReviewShortcut.allCases.compactMap(\.letter), ["w", "i", "e", "t"])
        XCTAssertNil(ReviewShortcut.check.letter)
        XCTAssertNil(ReviewShortcut.playAgain.letter)
    }
}
