import XCTest
import GRDB
@testable import LangCore

final class ResumePointTests: XCTestCase {
    func testOnlyTheMiddleOfAVideoIsWorthKeeping() {
        XCTAssertNil(ResumePoint.worthKeeping(2, duration: 300), "the first seconds")
        XCTAssertEqual(ResumePoint.worthKeeping(120, duration: 300), 120)
        XCTAssertNil(ResumePoint.worthKeeping(295, duration: 300), "the very end")
        XCTAssertNil(ResumePoint.worthKeeping(5, duration: 12), "a clip too short to resume")
        XCTAssertNil(ResumePoint.worthKeeping(.nan, duration: 300))
    }

    func testSavingAndClearingTheSpot() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d in
            var v = Video(language: "es", title: "uno", contentHash: "1", videoPath: "a", duration: 300); try v.insert(d); return v.id!
        }
        var video = try await db.video(id: id)
        XCTAssertNil(video?.resumePosition)

        try await db.saveResumePosition(videoID: id, seconds: 120)
        video = try await db.video(id: id)
        XCTAssertEqual(video?.resumePosition, 120)

        try await db.saveResumePosition(videoID: id, seconds: 299)   // finished: nothing to resume
        video = try await db.video(id: id)
        XCTAssertNil(video?.resumePosition)
    }
}
