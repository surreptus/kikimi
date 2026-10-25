import GRDB
import XCTest
@testable import LangCore

final class VideoStorageTests: XCTestCase {
    /// Two imported videos sharing the word "casa"; "grande" and "perro" appear in one each.
    private func library() async throws -> (env: LangEnvironment, a: Video, b: Video, sourceA: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let sourceA = dir.appending(path: "a.mov"), sourceB = dir.appending(path: "b.mov")
        try await FixtureVideo.make(at: sourceA, seconds: 2)
        try await FixtureVideo.make(at: sourceB, seconds: 3)   // different length, so different content hash

        let scripts = LockedBox([
            [TranscriptSegment(start: 0, end: 1, text: "La casa es grande.")],
            [TranscriptSegment(start: 0, end: 1, text: "La casa tiene un perro.")],
        ])
        let env = try LangEnvironment(
            root: dir.appending(path: "container"), defaults: UserDefaults(suiteName: "vs-\(UUID().uuidString)")!,
            transcriber: SequencedTranscriber(scripts: scripts))
        let a = try await env.pipeline.importVideo(from: sourceA, profile: SpanishProfile())
        let b = try await env.pipeline.importVideo(from: sourceB, profile: SpanishProfile())
        return (env, a, b, sourceA, dir)
    }

    private func lemma(_ env: LangEnvironment, _ name: String) async throws -> Word? {
        try await env.database.writer.read { try Word.filter(Column("lemma") == name).fetchOne($0) }
    }

    // MARK: Details

    func testDetailsReportSizesLocationAndCounts() async throws {
        let (env, a, _, _, _) = try await library()
        let details = try await env.details(for: a)
        let videoSize = try FileManager.default.attributesOfItem(atPath: env.fileURL(for: a).path)[.size] as! Int64

        XCTAssertEqual(details.videoBytes, videoSize)
        XCTAssertEqual(details.audioBytes, 0, "new imports keep no separate audio file")
        XCTAssertEqual(details.totalBytes, videoSize)
        XCTAssertGreaterThan(details.totalBytes, 0)
        XCTAssertEqual(details.subtitleCount, 1)
        XCTAssertEqual(details.wordCount, 3, "casa, ser (from es) and grande: content words only")
        XCTAssertTrue(details.folder.path.hasPrefix(env.libraryURL.standardizedFileURL.path + "/"))
        XCTAssertFalse(details.filesMissing)
        XCTAssertEqual(env.bytesOnDisk(for: a), details.totalBytes)
    }

    func testAnAudioFileFromAnEarlierVersionIsStillCountedAndRemoved() async throws {
        let (env, a, _, _, _) = try await library()
        var legacy = a
        legacy.audioPath = "\(a.contentHash)/audio.m4a"
        let file = env.libraryURL.appending(path: legacy.audioPath!)
        try Data(count: 1234).write(to: file)

        let details = try await env.details(for: legacy)
        XCTAssertEqual(details.audioBytes, 1234)
        XCTAssertEqual(details.totalBytes, details.videoBytes + 1234)
        XCTAssertEqual(env.bytesOnDisk(for: legacy), details.totalBytes)
    }

    func testLibraryBytesCoversEveryVideo() async throws {
        let (env, a, b, _, _) = try await library()
        XCTAssertGreaterThanOrEqual(env.libraryBytes(), env.bytesOnDisk(for: a) + env.bytesOnDisk(for: b))
    }

    // MARK: Delete

    func testDeleteRemovesTheAppsCopyOnlyAndFreesSpace() async throws {
        let (env, a, b, sourceA, _) = try await library()
        let originalBefore = try ImportHarness.snapshot(of: sourceA)
        let folder = env.libraryFolder(for: a)!
        let used = env.bytesOnDisk(for: a)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        let result = try await env.deleteVideo(a)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertGreaterThanOrEqual(result.freedBytes, used)
        XCTAssertEqual(try ImportHarness.snapshot(of: sourceA), originalBefore, "the user's original is never touched")
        let remaining = try await env.database.libraryVideos().map(\.video.id)
        XCTAssertEqual(remaining, [b.id])
        let lines = try await env.database.subtitles(videoID: a.id!)
        XCTAssertTrue(lines.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.fileURL(for: b).path), "other videos are untouched")
    }

    func testWordsKeepTheirProgressUnlessUntouchedAndOrphaned() async throws {
        let (env, a, _, _, _) = try await library()
        // "grande" appears only in video A. Start learning it: it must survive. "casa" is in both videos.
        let grande = try await lemma(env, "grande")!
        try await env.database.startLearning(wordID: grande.id!)

        // Make a word that is only in A and still "new": add it by hand so the test doesn't depend on tokenizing.
        let loneID = try await env.database.writer.write { db -> Int64 in
            var w = Word(language: "es", lemma: "soloenA", pos: .noun); try w.insert(db)
            let sub = try Subtitle.filter(Column("video_id") == a.id!).fetchOne(db)!
            var o = Occurrence(wordId: w.id!, subtitleId: sub.id!, surface: "soloenA"); try o.insert(db)
            return w.id!
        }

        let result = try await env.deleteVideo(a)

        XCTAssertEqual(result.removedWords, 2, "\"ser\" (from \"es\") and the hand-made word: new, and in no other video")
        let lone = try await env.database.writer.read { try Word.fetchOne($0, key: loneID) }
        XCTAssertNil(lone, "untouched word that no video contains is removed")
        let kept = try await lemma(env, "grande")
        XCTAssertEqual(kept?.status, .learning, "progress on a word is never discarded")
        let shared = try await lemma(env, "casa")
        XCTAssertNotNil(shared, "still appears in the other video")
        let examples = try await env.database.examples(wordID: shared!.id!)
        XCTAssertEqual(examples.count, 1)
    }

    func testTheSameFileCanBeImportedAgainAfterDeleting() async throws {
        let (env, a, _, sourceA, _) = try await library()
        try await env.deleteVideo(a)
        let again = try await env.pipeline.importVideo(from: sourceA, profile: SpanishProfile())
        XCTAssertEqual(again.contentHash, a.contentHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.fileURL(for: again).path))
    }

    func testDeleteStillWorksWhenFilesAreAlreadyGone() async throws {
        let (env, a, _, _, _) = try await library()
        try FileManager.default.removeItem(at: env.libraryFolder(for: a)!)
        let details = try await env.details(for: a)
        XCTAssertTrue(details.filesMissing)
        XCTAssertEqual(details.totalBytes, 0)
        try await env.deleteVideo(a)
        let remaining = try await env.database.libraryVideos().count
        XCTAssertEqual(remaining, 1)
    }

    func testDeleteRefusesPathsOutsideTheLibrary() async throws {
        let (env, a, _, _, dir) = try await library()
        let sentinel = dir.appending(path: "container/precious.txt")
        try Data("keep".utf8).write(to: sentinel)

        for bad in ["../precious.txt", "video.mov", "/etc/x/video.mov", "./x.mov", "../../x/video.mov", ""] {
            var evil = a
            evil.videoPath = bad
            do {
                try await env.deleteVideo(evil)
                XCTFail("expected refusal for \(bad)")
            } catch VideoStorageError.unsafePath {}
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let count = try await env.database.libraryVideos().count
        XCTAssertEqual(count, 2, "nothing was removed from the database either")
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.fileURL(for: a).path))
    }

    func testDeletingAnUnknownVideoFails() async throws {
        let (env, a, _, _, _) = try await library()
        var ghost = a
        ghost.id = 9999
        do {
            try await env.deleteVideo(ghost)
            XCTFail("expected notFound")
        } catch LangError.notFound {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.fileURL(for: a).path), "files stay if the row doesn't exist")
    }
}

/// Hands out one scripted transcript per call, in order.
struct SequencedTranscriber: Transcriber {
    let scripts: LockedBox<[[TranscriptSegment]]>

    func transcribe(
        mediaURL: URL, whisperCode: String, model: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        scripts.mutateReturning { $0.isEmpty ? [] : $0.removeFirst() }
    }
}
