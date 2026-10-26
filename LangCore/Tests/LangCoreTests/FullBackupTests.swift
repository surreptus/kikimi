import GRDB
import XCTest
@testable import LangCore

final class FullBackupTests: XCTestCase {
    private func scratch() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "full-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func env(in dir: URL, name: String) throws -> LangEnvironment {
        try LangEnvironment(
            root: dir.appending(path: name), defaults: UserDefaults(suiteName: "full-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([
                TranscriptSegment(start: 1, end: 2, text: "La casa es grande."),
                TranscriptSegment(start: 3.5, end: 5, text: "Corremos a la casa."),
            ])))
    }

    /// An environment with one imported video and "casa" being learned.
    private func source(in dir: URL) async throws -> LangEnvironment {
        let video = dir.appending(path: "clip.mov")
        try await FixtureVideo.make(at: video, seconds: 6)
        let a = try env(in: dir, name: "a")
        _ = try await a.pipeline.importVideo(from: video, profile: SpanishProfile())
        let casa = try await a.database.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        try await a.database.startLearning(wordID: casa)
        try await a.database.writer.write { try $0.execute(sql: "UPDATE videos SET resume_position = 3") }   // the fixture is too short for saveResumePosition
        return a
    }

    func testASavedBackupHoldsProgressTranscriptsAndTheCompressedVideo() async throws {
        let dir = scratch()
        let a = try await source(in: dir)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let summary = try await a.writeFullBackup(in: out, name: "Backup")
        XCTAssertEqual(summary.videos, 1)
        XCTAssertGreaterThan(summary.bytes, 0)
        XCTAssertTrue(LangEnvironment.isFullBackup(summary.folder))
        for file in ["progress.kikimi", "library.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: summary.folder.appending(path: file).path), file)
        }
        let library = try FileManager.default.contentsOfDirectory(atPath: summary.folder.appending(path: "Library").path)
        XCTAssertEqual(library.count, 1, "one folder per video")

        let again = try await a.writeFullBackup(in: out, name: "Backup")
        XCTAssertNotEqual(again.folder, summary.folder, "an earlier backup is never overwritten")
        XCTAssertFalse(LangEnvironment.isFullBackup(dir), "an ordinary folder is not a backup")
    }

    func testRestoringOnAnotherMacBringsBackTheVideoTheTranscriptAndTheProgress() async throws {
        let dir = scratch()
        let a = try await source(in: dir)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let backup = try await a.writeFullBackup(in: out, name: "Backup").folder

        let b = try env(in: dir, name: "b")
        let preview = try await b.previewFullBackup(at: backup)
        XCTAssertEqual(preview.videosToAdd, 1)
        XCTAssertEqual(preview.videosAlreadyHere, 0)
        XCTAssertGreaterThan(preview.bytesToCopy, 0)

        let result = try await b.restoreFullBackup(from: backup, includingSettings: false)
        XCTAssertEqual(result.videosAdded, 1)
        let video = try await b.database.video(id: 1)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.fileURL(for: video).path), "the video file is back")
        XCTAssertEqual(video.resumePosition, 3)
        let lines = try await b.database.subtitles(videoID: 1)
        XCTAssertEqual(lines.map(\.text), ["La casa es grande.", "Corremos a la casa."], "no re-transcribing")
        let casa = try await b.database.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)! }
        XCTAssertEqual(casa.status, .learning, "progress is applied to the words found again")
        let seen = try await b.database.seen(wordID: casa.id!)
        XCTAssertEqual(seen.lines, 2)

        // Running it again changes nothing.
        let second = try await b.restoreFullBackup(from: backup, includingSettings: false)
        XCTAssertEqual(second.videosAdded, 0)
        let count = try await b.database.writer.read { try Video.fetchCount($0) }
        XCTAssertEqual(count, 1)
        let preview2 = try await b.previewFullBackup(at: backup)
        XCTAssertEqual(preview2.videosAlreadyHere, 1)
    }

    func testAFolderWithAnUnsafePathOrMissingFilesAddsNothing() async throws {
        let dir = scratch()
        let a = try await source(in: dir)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let backup = try await a.writeFullBackup(in: out, name: "Backup").folder

        // Point the video at a path outside its own folder.
        let file = backup.appending(path: "library.json")
        var text = try String(contentsOf: file, encoding: .utf8)
        let hash = try await a.database.video(id: 1)!.contentHash
        text = text.replacingOccurrences(of: "\"\(hash)/video.mov\"", with: "\"../../escape/video.mov\"")
        try text.write(to: file, atomically: true, encoding: .utf8)

        let b = try env(in: dir, name: "b")
        let preview = try await b.previewFullBackup(at: backup)
        XCTAssertEqual(preview.videosToAdd, 0)
        XCTAssertEqual(preview.videosMissingFiles, 1)
        let result = try await b.restoreFullBackup(from: backup, includingSettings: false)
        XCTAssertEqual(result.videosAdded, 0)
        let count = try await b.database.writer.read { try Video.fetchCount($0) }
        XCTAssertEqual(count, 0)
    }

    func testAProgressOnlyFolderStillRestoresProgress() async throws {
        let dir = scratch()
        let a = try await source(in: dir)
        let folder = dir.appending(path: "progress-only", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await a.makeBackup().write(to: folder.appending(path: LangEnvironment.progressFileName))
        let b = try env(in: dir, name: "b")
        let preview = try await b.previewFullBackup(at: folder)
        XCTAssertEqual(preview.videosToAdd, 0)
        let result = try await b.restoreFullBackup(from: folder, includingSettings: false)
        XCTAssertEqual(result.videosAdded, 0)
    }
}
