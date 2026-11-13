import XCTest
@testable import LangCore

/// Every message the learner can read must be plain, and the raw text must stay available as `detail`.
final class ErrorMessageTests: XCTestCase {
    private struct Raw: LocalizedError {
        var errorDescription: String? { "SQLite error 13: database or disk is full" }
    }

    private let banned = ["re-encode", "reencode", "verification", "database", "transcode", "staging", "sqlite", "grdb", "avfoundation", "error code"]

    private var errors: [any DetailedError] {
        let raw = Raw()
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let subtitleProblems: [SubtitleProblem] = [.unreadable, .noSubtitles, .outsideVideo, .otherLanguage(name: "French")]
        var all: [any DetailedError] = [
            ImportError.duplicate(existingVideoID: 3),
            ImportError.languageMismatch(detected: "ja", chosen: "es", confidence: 0.9),
            ImportError.copyFailed(raw),
            ImportError.transcriptionFailed(raw),
            ImportError.transcriptionFailed(ModelError.notInstalled("m")),
            ImportError.transcriptionFailed(AudioExtractionError.noAudioTrack),
            ImportError.transcodeFailed(raw),
            ImportError.transcodeFailed(TranscodeError.writerFailed(raw)),
            ImportError.verificationFailed("output is not playable"),
            ImportError.libraryMoveFailed(raw),
            ImportError.databaseFailed(raw),
            ModelError.notInstalled("m"), ModelError.busy("m"), ModelError.incomplete("m", missing: ["a"]),
            VideoStorageError.unsafePath("/tmp/x"), VideoStorageError.filesRemain(url),
            BackupError.notABackup, BackupError.newerVersion(9), BackupError.damaged,
            TranscodeError.presetUnavailable("p"), TranscodeError.noVideoTrack,
            TranscodeError.readerFailed(raw), TranscodeError.readerFailed(nil), TranscodeError.writerFailed(raw),
            AudioExtractionError.noAudioTrack, AudioExtractionError.readerFailed(raw),
            LangError.notFound, LangError.notLearning, LangError.emptyTitle, LangError.emptyLine, LangError.badTiming,
            DictionaryError.missingResource("d"), MeCabError.modelFailed("m"),
            ClipError.missingSource(url), ClipError.emptyRange, ClipError.presetUnavailable,
        ]
        all += subtitleProblems.map { ImportError.subtitlesUnusable($0) }
        return all
    }

    func testNoPlainMessageUsesTechnicalWords() {
        for error in errors {
            let message = (error.errorDescription ?? "").lowercased()
            XCTAssertFalse(message.isEmpty, "\(error) has no message")
            for word in banned { XCTAssertFalse(message.contains(word), "\"\(message)\" contains \"\(word)\"") }
            XCTAssertFalse(message.contains("(null)") || message.contains("error 13"), "\(message)")
        }
    }

    func testEveryMessageHasDetail() {
        for error in errors { XCTAssertFalse(error.detail.isEmpty, "\(error)") }
    }

    func testDetailKeepsTheUnderlyingText() {
        let raw = Raw()
        for error in [ImportError.copyFailed(raw), .transcodeFailed(raw), .libraryMoveFailed(raw), .databaseFailed(raw), .transcriptionFailed(raw)] {
            XCTAssertTrue(error.detail.contains("SQLite error 13"), error.detail)
        }
        XCTAssertTrue(ImportError.verificationFailed("output has no video track").detail.contains("output has no video track"))
        XCTAssertTrue(ImportError.transcodeFailed(TranscodeError.writerFailed(raw)).detail.contains("SQLite error 13"))
        XCTAssertTrue(ModelError.incomplete("m", missing: ["AudioEncoder/weight.bin"]).detail.contains("AudioEncoder/weight.bin"))
        XCTAssertTrue(VideoStorageError.filesRemain(URL(fileURLWithPath: "/tmp/x.mp4")).detail.contains("/tmp/x.mp4"))
    }

    func testProblemOfOurOwnErrorUsesItsMessageAndDetail() {
        let problem = Problem(ModelError.notInstalled("openai_whisper-small"), fallback: "unused")
        XCTAssertEqual(problem.message, ModelError.notInstalled("x").errorDescription)
        XCTAssertTrue(problem.detail.contains("openai_whisper-small"))
    }

    func testProblemOfAnyOtherErrorUsesTheFallbackAndKeepsTheRawText() {
        let problem = Problem(Raw(), fallback: "Kikimi couldn't do that. Try again.")
        XCTAssertEqual(problem.message, "Kikimi couldn't do that. Try again.")
        XCTAssertTrue(problem.detail.contains("SQLite error 13"))
        let system = Problem(CocoaError(.fileWriteOutOfSpace), fallback: "f")
        XCTAssertEqual(system.message, "f")
        XCTAssertTrue(system.detail.contains("NSCocoaErrorDomain"), system.detail)
    }

    @MainActor func testFailedImportJobShowsPlainMessageAndKeepsDetail() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline())
        queue.enqueue([h.dir.appending(path: "nope.mov")], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        guard case .failed(let problem) = queue.jobs[0].status else { return XCTFail("expected failure") }
        let message = problem.message.lowercased()
        for word in banned { XCTAssertFalse(message.contains(word), message) }
        XCTAssertFalse(problem.detail.isEmpty)
    }
}
