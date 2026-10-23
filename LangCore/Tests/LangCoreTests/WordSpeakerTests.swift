import XCTest
@testable import LangCore

final class VoiceSelectionTests: XCTestCase {
    private func voice(_ id: String, _ language: String, _ quality: Int) -> VoiceChoice {
        VoiceChoice(identifier: id, name: id, language: language, quality: quality)
    }

    func testHigherQualityWinsWhateverTheRegion() {
        let voices = [voice("a", "es-ES", 1), voice("b", "es-MX", 3), voice("c", "es-AR", 2)]
        XCTAssertEqual(VoiceSelection.best(in: voices, forLanguage: "es")?.identifier, "b")
    }

    func testOnlyTheRequestedLanguageMatches() {
        let voices = [voice("en", "en-US", 3), voice("ja", "ja-JP", 1), voice("est", "et-EE", 3)]
        XCTAssertEqual(VoiceSelection.best(in: voices, forLanguage: "ja")?.identifier, "ja")
        XCTAssertNil(VoiceSelection.best(in: voices, forLanguage: "es"))
        XCTAssertNil(VoiceSelection.best(in: voices, forLanguage: "e"), "a prefix of the code is not a match")
    }

    func testEquallyGoodVoicesGiveTheSameAnswerEveryTime() {
        let voices = [voice("z", "es-ES", 2), voice("m", "es-MX", 2), voice("a", "es-AR", 2)]
        XCTAssertEqual(VoiceSelection.best(in: voices, forLanguage: "es")?.identifier, "a")
        XCTAssertEqual(VoiceSelection.best(in: voices.reversed(), forLanguage: "es")?.identifier, "a")
    }

    func testStandardVoicesOutrankEloquenceOnesAtTheSameQuality() {
        let voices = [
            VoiceChoice(identifier: "com.apple.eloquence.es-ES.Eddy", name: "Eddy", language: "es-ES", quality: 1),
            VoiceChoice(identifier: "com.apple.voice.compact.es-ES.Monica", name: "Mónica", language: "es-ES", quality: 1),
        ]
        XCTAssertEqual(VoiceSelection.best(in: voices, forLanguage: "es")?.name, "Mónica")
        // Quality still comes first: a better Eloquence voice beats a worse standard one.
        let better = voices + [VoiceChoice(identifier: "com.apple.eloquence.es-ES.Flo", name: "Flo", language: "es-ES", quality: 2)]
        XCTAssertEqual(VoiceSelection.best(in: better, forLanguage: "es")?.name, "Flo")
    }

    func testLanguageTagsAreMatchedLoosely() {
        XCTAssertNotNil(VoiceSelection.best(in: [voice("a", "ES_es", 1)], forLanguage: "es"))
        XCTAssertNotNil(VoiceSelection.best(in: [voice("a", "ja", 1)], forLanguage: "JA"))
        XCTAssertNil(VoiceSelection.best(in: [], forLanguage: "es"))
    }

    func testInstalledVoicesAreWellFormed() {
        for voice in WordSpeaker.installedChoices() {
            XCTAssertFalse(voice.identifier.isEmpty)
            XCTAssertTrue((1...3).contains(voice.quality), "\(voice.name): \(voice.quality)")
        }
    }
}
