import XCTest
@testable import LangCore

final class SRSTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testIntervals() {
        let h: TimeInterval = 3600, d: TimeInterval = 86400
        XCTAssertEqual(SRS.intervals, [4 * h, 8 * h, 23 * h, 47 * h, 7 * d, 14 * d, 30 * d, 120 * d])
        XCTAssertNil(SRS.interval(for: .burned))
    }

    func testCorrectAdvancesThroughEveryStage() {
        var stage = SRSStage.apprentice1
        for expected in SRSStage.allCases.dropFirst() {
            let r = SRS.answer(stage: stage, correct: true, now: now)
            XCTAssertEqual(r.stage, expected)
            if expected == .burned {
                XCTAssertNil(r.nextReview)
            } else {
                XCTAssertEqual(r.nextReview, now.addingTimeInterval(SRS.interval(for: expected)!))
            }
            stage = r.stage
        }
    }

    func testWrongDropsOneStage() {
        for stage in SRSStage.allCases.dropFirst().dropLast() {
            let r = SRS.answer(stage: stage, correct: false, now: now)
            XCTAssertEqual(r.stage.rawValue, stage.rawValue - 1)
            XCTAssertEqual(r.nextReview, now.addingTimeInterval(SRS.interval(for: r.stage)!))
        }
    }

    func testWrongNeverBelowStageOne() {
        let r = SRS.answer(stage: .apprentice1, correct: false, now: now)
        XCTAssertEqual(r.stage, .apprentice1)
        XCTAssertEqual(r.nextReview, now.addingTimeInterval(4 * 3600))
    }

    func testBurnedIsTerminal() {
        for correct in [true, false] {
            let r = SRS.answer(stage: .burned, correct: correct, now: now)
            XCTAssertEqual(r.stage, .burned)
            XCTAssertNil(r.nextReview)
        }
    }
}
