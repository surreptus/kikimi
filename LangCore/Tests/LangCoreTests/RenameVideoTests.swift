import XCTest
@testable import LangCore

final class RenameVideoTests: XCTestCase {
    func testRenamingChangesOnlyTheTitle() async throws {
        let db = try LangDatabase()
        let video = try await db.saveImport(
            video: Video(language: "es", title: "clip", contentHash: "h", videoPath: "h/video.mov", audioPath: "h/audio.m4a", duration: 5),
            subtitles: [])
        try await db.renameVideo(id: video.id!, to: "  Mi viaje a Italia \n")
        let renamed = try await db.video(id: video.id!)
        XCTAssertEqual(renamed?.title, "Mi viaje a Italia", "trimmed")
        XCTAssertEqual(renamed?.videoPath, "h/video.mov")
        XCTAssertEqual(renamed?.contentHash, "h")
    }

    func testEmptyAndUnknownAreRejected() async throws {
        let db = try LangDatabase()
        let video = try await db.saveImport(
            video: Video(language: "es", title: "clip", contentHash: "h", videoPath: "v", duration: 5), subtitles: [])
        for bad in ["", "   ", "\n"] {
            do { try await db.renameVideo(id: video.id!, to: bad); XCTFail("expected emptyTitle") }
            catch LangError.emptyTitle {}
        }
        do { try await db.renameVideo(id: 999, to: "x"); XCTFail("expected notFound") }
        catch LangError.notFound {}
        let unchanged = try await db.video(id: video.id!)
        XCTAssertEqual(unchanged?.title, "clip")
    }

    func testRenamingKeepsDuplicateDetectionByContent() async throws {
        let h = try await ImportHarness()
        let first = try await h.pipeline().importVideo(from: h.original, profile: SpanishProfile())
        try await h.database.renameVideo(id: first.id!, to: "Something else")
        do {
            _ = try await h.pipeline().importVideo(from: h.original, profile: SpanishProfile())
            XCTFail("expected duplicate")
        } catch ImportError.duplicate {}
    }
}
