import XCTest
@testable import LangCore

final class LanguageGuessTests: XCTestCase {
    func testProbabilitiesAreNormalisedToAConfidence() {
        let guess = LanguageGuess.best(from: ["es": 0.9, "ja": 0.05, "en": 0.05])!
        XCTAssertEqual(guess.code, "es")
        XCTAssertEqual(guess.confidence, 0.9, accuracy: 0.001)
    }

    func testLogProbabilitiesWork() {
        // The same 90/5/5 split expressed as natural logs.
        let guess = LanguageGuess.best(from: ["es": Float(log(0.9)), "ja": Float(log(0.05)), "en": Float(log(0.05))])!
        XCTAssertEqual(guess.code, "es")
        XCTAssertEqual(guess.confidence, 0.9, accuracy: 0.01)
    }

    func testALoneLogProbabilityIsItsOwnConfidence() {
        // This is what WhisperKit really returns: only the winner, with its log-probability.
        XCTAssertEqual(LanguageGuess.best(from: ["ja": Float(log(0.83))])!.confidence, 0.83, accuracy: 0.001)
        XCTAssertEqual(LanguageGuess.best(from: ["en": Float(log(0.31))])!.confidence, 0.31, accuracy: 0.001)
        XCTAssertEqual(LanguageGuess.best(from: ["es": 0])!.confidence, 1.0, "a log-probability of 0 is certainty")
        XCTAssertEqual(LanguageGuess.best(from: ["es": 0.7])!.confidence, 0.7, accuracy: 0.001, "a plain probability is kept")
    }

    func testAnEvenSplitIsLowConfidence() {
        let guess = LanguageGuess.best(from: ["es": 0.34, "ja": 0.33, "en": 0.33])!
        XCTAssertLessThan(guess.confidence, 0.6)
    }

    func testEmptyOrZeroScoresGiveNoGuess() {
        XCTAssertNil(LanguageGuess.best(from: [:]))
        XCTAssertNil(LanguageGuess.best(from: ["es": 0, "ja": 0]))
    }
}

final class LanguageGuardTests: XCTestCase {
    private let spanish = SpanishProfile()

    private func attempt(_ detection: LanguageGuess?, fails: Bool = false, check: Bool = true) async throws -> (ImportHarness, Result<Video, Error>) {
        let h = try await ImportHarness()
        var transcriber = StubTranscriber(result: .success(spanishSegments))
        transcriber.detected = detection
        transcriber.detectionFails = fails
        do {
            let video = try await h.pipeline(transcriber: transcriber).importVideo(from: h.original, profile: spanish, checkLanguage: check)
            return (h, .success(video))
        } catch {
            return (h, .failure(error))
        }
    }

    func testAJapaneseFileImportedAsSpanishIsStoppedBeforeAnythingChanges() async throws {
        let (h, result) = try await attempt(LanguageGuess(code: "ja", confidence: 0.97))
        guard case .failure(ImportError.languageMismatch(let detected, let chosen, let confidence)) = result else {
            return XCTFail("expected a language mismatch, got \(result)")
        }
        XCTAssertEqual(detected, "ja")
        XCTAssertEqual(chosen, "es")
        XCTAssertEqual(confidence, 0.97, accuracy: 0.001)
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
        XCTAssertEqual(ImportError.languageMismatch(detected: "ja", chosen: "es", confidence: 0.9).errorDescription,
                       "This sounds like Japanese, not Spanish.")
    }

    func testMatchingLanguageImportsNormally() async throws {
        let (_, result) = try await attempt(LanguageGuess(code: "es", confidence: 0.99))
        guard case .success(let video) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(video.language, "es")
    }

    func testUnsureDetectionDoesNotBlock() async throws {
        let (_, result) = try await attempt(LanguageGuess(code: "ja", confidence: 0.45))
        guard case .success = result else { return XCTFail("a weak guess must not stop an import: \(result)") }
    }

    func testALanguageWeDontSupportDoesNotBlock() async throws {
        // Italian chatter in a Spanish vlog, or an English video: not a case for a hard stop.
        let (_, result) = try await attempt(LanguageGuess(code: "it", confidence: 0.95))
        guard case .success = result else { return XCTFail("\(result)") }
    }

    func testDetectionFailureOrNoAnswerDoesNotBlock() async throws {
        let (_, failed) = try await attempt(nil, fails: true)
        guard case .success = failed else { return XCTFail("\(failed)") }
        let (_, unknown) = try await attempt(nil)
        guard case .success = unknown else { return XCTFail("\(unknown)") }
    }

    func testCheckCanBeSkipped() async throws {
        let (_, result) = try await attempt(LanguageGuess(code: "ja", confidence: 0.99), check: false)
        guard case .success(let video) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(video.language, "es", "imported as chosen")
    }
}

@MainActor
final class LanguageQueueTests: XCTestCase {
    private func queue(detecting guess: LanguageGuess) async throws -> (ImportHarness, ImportQueue) {
        let h = try await ImportHarness()
        var transcriber = StubTranscriber(result: .success(spanishSegments))
        transcriber.detected = guess
        return (h, ImportQueue(pipeline: h.pipeline(transcriber: transcriber)))
    }

    func testMismatchWaitsForADecision() async throws {
        let (h, queue) = try await queue(detecting: LanguageGuess(code: "ja", confidence: 0.95))
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()

        XCTAssertEqual(queue.jobs[0].status, .languageMismatch(detected: "ja"))
        XCTAssertFalse(queue.isBusy, "waiting for you isn't busy")
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testImportAnywayKeepsTheChosenLanguage() async throws {
        let (h, queue) = try await queue(detecting: LanguageGuess(code: "ja", confidence: 0.95))
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        queue.importAnyway(queue.jobs[0].id)
        await queue.waitUntilIdle()

        XCTAssertEqual(queue.jobs[0].status, .imported)
        let language = try await h.database.libraryVideos().first?.video.language
        XCTAssertEqual(language, "es")
    }

    func testRetryAsTheDetectedLanguage() async throws {
        let (h, queue) = try await queue(detecting: LanguageGuess(code: "ja", confidence: 0.95))
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        queue.retry(queue.jobs[0].id, as: JapaneseProfile(), model: "m-ja")
        await queue.waitUntilIdle()

        // The stub still "hears" Japanese, which now matches the chosen profile, so it imports as Japanese.
        XCTAssertEqual(queue.jobs[0].status, .imported)
        XCTAssertEqual(queue.jobs[0].profile.code, "ja")
        let language = try await h.database.libraryVideos().first?.video.language
        XCTAssertEqual(language, "ja")
    }

    func testEachJobKeepsItsOwnLanguageDecision() async throws {
        let h = try await ImportHarness()
        var transcriber = StubTranscriber(result: .success(spanishSegments))
        transcriber.detected = LanguageGuess(code: "es", confidence: 0.99)
        let queue = ImportQueue(pipeline: h.pipeline(transcriber: transcriber))
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs[0].status, .imported)
        XCTAssertEqual(queue.jobs[0].profile.displayName, "Spanish", "the UI can say which language it went into")
    }
}
