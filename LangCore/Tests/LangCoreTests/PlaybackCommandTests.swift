import XCTest
@testable import LangCore

final class PlaybackCommandTests: XCTestCase {
    private func available(ready: Bool = true, editing: Bool = false, word: Bool = true, _ status: WordStatus? = .new) -> Set<PlaybackCommand> {
        PlaybackCommand.available(videoReady: ready, editingLine: editing, hasWord: word, status: status)
    }

    private let player: Set<PlaybackCommand> = [.playPause, .previousLine, .nextLine, .pauseAfterLine, .hideSubtitles, .loopLine, .focusTranscript]

    func testNothingWorksBeforeTheVideoIsReadyOrWhileALineIsEdited() {
        XCTAssertEqual(available(ready: false), [])
        XCTAssertEqual(available(editing: true), [], "the edit sheet has text fields: no bare key may leave it")
    }

    func testWithoutAWordOnlyThePlayerCommandsWork() {
        XCTAssertEqual(available(word: false), player)
    }

    func testANewWordCanBeLearnedKnownOrIgnored() {
        XCTAssertEqual(available(.new), player.union([.learnWord, .knownWord, .ignoreWord]))
        XCTAssertEqual(available(nil), player.union([.learnWord, .knownWord]), "a word with no status yet is not ignorable")
    }

    func testEachStatusOffersWhatItCanMoveTo() {
        XCTAssertEqual(available(.learning), player.union([.knownWord]))
        XCTAssertEqual(available(.known), player.union([.learnWord]))
        XCTAssertEqual(available(.finished), player.union([.knownWord]))
        XCTAssertEqual(available(.ignored), player.union([.restoreWord]))
    }
}
