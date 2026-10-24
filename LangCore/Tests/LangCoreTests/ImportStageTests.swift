import XCTest
@testable import LangCore

final class ImportStageTests: XCTestCase {
    func testEightStepsInOrderWhenTheLanguageIsChecked() {
        XCTAssertEqual(ImportStage.steps(checkingLanguage: true),
                       [.hashing, .staging, .detectingLanguage, .transcribing, .transcoding, .verifying, .extractingAudio, .saving])
        let first = ImportStage.hashing.position(checkingLanguage: true)
        XCTAssertEqual(first.number, 1); XCTAssertEqual(first.of, 8)
        let last = ImportStage.saving.position(checkingLanguage: true)
        XCTAssertEqual(last.number, 8); XCTAssertEqual(last.of, 8)
    }

    func testSkippingTheLanguageCheckRenumbersTheRest() {
        XCTAssertEqual(ImportStage.steps(checkingLanguage: false).count, 7)
        XCTAssertFalse(ImportStage.steps(checkingLanguage: false).contains(.detectingLanguage))
        let transcribing = ImportStage.transcribing.position(checkingLanguage: false)
        XCTAssertEqual(transcribing.number, 3, "it was 4 of 8 with the check")
        XCTAssertEqual(transcribing.of, 7)
        let last = ImportStage.saving.position(checkingLanguage: false)
        XCTAssertEqual(last.number, 7); XCTAssertEqual(last.of, 7)
    }

    func testEveryStageHasAPositionBetweenOneAndTheTotal() {
        for checking in [true, false] {
            for stage in ImportStage.steps(checkingLanguage: checking) {
                let p = stage.position(checkingLanguage: checking)
                XCTAssertTrue((1...p.of).contains(p.number), "\(stage)")
            }
        }
    }
}
