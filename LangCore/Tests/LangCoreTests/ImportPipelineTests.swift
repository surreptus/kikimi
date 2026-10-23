import AVFoundation
import GRDB
import XCTest
@testable import LangCore

final class ImportPipelineTests: XCTestCase {
    let spanish = SpanishProfile()

    // MARK: Success

    func testSuccessfulImport() async throws {
        let h = try await ImportHarness()
        let video = try await h.pipeline().importVideo(from: h.original, profile: spanish)

        try h.assertOriginalUntouched()
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.original.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.container.appending(path: "Staging").path), [])

        let library = h.container.appending(path: "Library")
        let videoURL = library.appending(path: video.videoPath)
        let audioURL = library.appending(path: video.audioPath!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))

        let asset = AVURLAsset(url: videoURL)
        let seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(seconds, 2, accuracy: 0.2)
        let sourceBytes = AVFoundationTranscoder.fileSize(h.original)
        XCTAssertLessThanOrEqual(AVFoundationTranscoder.fileSize(videoURL), sourceBytes + max(8_000, sourceBytes / 10),
                                 "the library copy is never bigger than the file you dropped")

        try await h.database.writer.read { db in
            XCTAssertEqual(try Video.fetchCount(db), 1)
            XCTAssertEqual(try Subtitle.fetchCount(db), 2)
            let casa = try Word.filter(Column("lemma") == "casa").fetchOne(db)
            XCTAssertNotNil(casa)
            XCTAssertEqual(try Occurrence.filter(Column("word_id") == casa!.id!).fetchCount(db), 2)
            XCTAssertNil(try Word.filter(Column("lemma") == "la").fetchOne(db), "function words excluded")
        }
    }

    func testProgressStagesAreReportedInOrder() async throws {
        let h = try await ImportHarness()
        let seen = LockedBox<[ImportStage]>([])
        _ = try await h.pipeline().importVideo(from: h.original, profile: spanish) { p in
            seen.mutate { if $0.last != p.stage { $0.append(p.stage) } }
        }
        XCTAssertEqual(seen.value, [.hashing, .staging, .detectingLanguage, .transcribing, .transcoding, .verifying,
                                    .extractingAudio, .saving])
    }

    // MARK: Duplicates

    func testDuplicateByContentIsRejectedEvenWithDifferentName() async throws {
        let h = try await ImportHarness()
        let pipeline = h.pipeline()
        let first = try await pipeline.importVideo(from: h.original, profile: spanish)

        let copy = h.dir.appending(path: "originals/renamed copy.mov")
        try FileManager.default.copyItem(at: h.original, to: copy)
        do {
            _ = try await pipeline.importVideo(from: copy, profile: spanish)
            XCTFail("expected duplicate")
        } catch ImportError.duplicate(let id) {
            XCTAssertEqual(id, first.id)
        }
        try await h.database.writer.read { XCTAssertEqual(try Video.fetchCount($0), 1) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.container.appending(path: "Staging").path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    // MARK: Failure modes: the original is untouched and nothing is left behind

    func testTranscriptionFailure() async throws {
        let h = try await ImportHarness()
        let pipeline = h.pipeline(transcriber: StubTranscriber(result: .failure(Failure())))
        await assertFails(.transcriptionFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testTranscodeFailure() async throws {
        let h = try await ImportHarness()
        let pipeline = h.pipeline(transcoder: StubTranscoder(hevc: { _, _ in throw Failure() }))
        await assertFails(.transcodeFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testVerificationFailsForUnreadableOutput() async throws {
        let h = try await ImportHarness()
        let garbage = StubTranscoder(hevc: { _, dest in try Data("not a video".utf8).write(to: dest) })
        let pipeline = h.pipeline(transcoder: garbage)
        await assertFails(.verificationFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testVerificationFailsWithoutVideoTrack() async throws {
        let h = try await ImportHarness()
        let audioOnly = StubTranscoder(hevc: { source, dest in
            try await AVFoundationTranscoder().extractAAC(source: source, destination: dest)
        })
        let pipeline = h.pipeline(transcoder: audioOnly)
        await assertFails(.verificationFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testVerificationFailsOnDurationMismatch() async throws {
        let h = try await ImportHarness(seconds: 2)
        let wrongLength = StubTranscoder(hevc: { _, dest in try await FixtureVideo.make(at: dest, seconds: 5) })
        let pipeline = h.pipeline(transcoder: wrongLength)
        await assertFails(.verificationFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testAudioExportFailure() async throws {
        let h = try await ImportHarness()
        let pipeline = h.pipeline(transcoder: StubTranscoder(aac: { _, _ in throw Failure() }))
        await assertFails(.audioExportFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testDatabaseWriteFailureRollsBackAndRemovesLibraryFiles() async throws {
        let h = try await ImportHarness()
        // Fail late in the transaction, after the video and subtitle rows were written.
        try await h.database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_occurrence BEFORE INSERT ON occurrences
                BEGIN SELECT RAISE(ABORT, 'injected failure'); END
                """)
        }
        let pipeline = h.pipeline()
        await assertFails(.databaseFailed) { _ = try await pipeline.importVideo(from: h.original, profile: spanish) }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()   // includes: library dir moved in step 6 was removed again
    }

    func testFailedImportCanBeRetried() async throws {
        let h = try await ImportHarness()
        let failing = h.pipeline(transcriber: StubTranscriber(result: .failure(Failure())))
        _ = try? await failing.importVideo(from: h.original, profile: spanish)
        let video = try await h.pipeline().importVideo(from: h.original, profile: spanish)
        XCTAssertNotNil(video.id)
        try h.assertOriginalUntouched()
    }

    // MARK: Helpers

    func testCleanOrphanedStagingRemovesLeftovers() async throws {
        let h = try await ImportHarness()
        let leftover = h.container.appending(path: "Staging/crashed")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appending(path: "source.mov"))
        await h.pipeline().cleanOrphanedStaging()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.container.appending(path: "Staging").path), [])
        try h.assertOriginalUntouched()
    }

    func testAudioExtractionProduces16kMono() async throws {
        let h = try await ImportHarness(seconds: 2)
        let samples = try await AudioExtractor.pcm16kMono(from: h.original)
        XCTAssertEqual(Double(samples.count), 32_000, accuracy: 2_000)
        let rms = (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
        XCTAssertGreaterThan(rms, 0.1, "tone should survive decoding and resampling")
    }

    private enum Expected { case transcriptionFailed, transcodeFailed, verificationFailed, audioExportFailed, databaseFailed }

    private func assertFails(
        _ expected: Expected, file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as ImportError {
            switch (error, expected) {
            case (.transcriptionFailed, .transcriptionFailed), (.transcodeFailed, .transcodeFailed),
                 (.verificationFailed, .verificationFailed), (.audioExportFailed, .audioExportFailed),
                 (.databaseFailed, .databaseFailed): break
            default: XCTFail("expected \(expected), got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
    func mutateReturning<R>(_ change: (inout T) -> R) -> R { lock.withLock { change(&stored) } }
}
