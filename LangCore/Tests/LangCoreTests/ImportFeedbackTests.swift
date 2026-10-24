import XCTest
@testable import LangCore

final class ProgressEstimateTests: XCTestCase {
    func testSaysNothingUntilThereIsSomethingToJudgeBy() {
        XCTAssertNil(ProgressEstimate.secondsLeft(elapsed: 30, fraction: 0.02), "under 5% is too early")
        XCTAssertNil(ProgressEstimate.secondsLeft(elapsed: 5, fraction: 0.5), "under 8 seconds is too early")
        XCTAssertNil(ProgressEstimate.secondsLeft(elapsed: 60, fraction: 1), "a finished step has nothing left")
        XCTAssertNil(ProgressEstimate.secondsLeft(elapsed: 60, fraction: 0))
    }

    func testEstimatesFromThePaceSoFar() throws {
        XCTAssertEqual(try XCTUnwrap(ProgressEstimate.secondsLeft(elapsed: 60, fraction: 0.5)), 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ProgressEstimate.secondsLeft(elapsed: 30, fraction: 0.25)), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ProgressEstimate.secondsLeft(elapsed: 100, fraction: 0.8)), 25, accuracy: 0.001)
    }

    func testPhrasesAreRoundedAndReadNaturally() {
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 10), "less than a minute left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 44), "less than a minute left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 60), "about 1 min left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 180), "about 3 min left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 8 * 60 + 20), "about 8 min left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 12 * 60), "about 10 min left", "five-minute steps above ten")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 3600), "about 1 h left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: 4200), "about 1 h 10 min left")
        XCTAssertEqual(ProgressEstimate.phrase(secondsLeft: -5), "less than a minute left")
    }
}

/// A transcriber whose model takes a moment to load, so the pipeline's "loading" note can be seen.
private actor SlowModelTranscriber: Transcriber {
    private var loaded = false
    private(set) var loadCount = 0
    let preloaded: Bool
    init(preloaded: Bool = false) { self.preloaded = preloaded; loaded = preloaded }

    func isModelLoaded(_ model: String) async -> Bool { loaded }
    func loadModel(_ model: String) async throws {
        loadCount += 1
        try await Task.sleep(for: .milliseconds(150))
        loaded = true
    }
    func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? { nil }
    func transcribe(mediaURL: URL, whisperCode: String, model: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        [TranscriptSegment(start: 0, end: 1, text: "La casa es grande.")]
    }
}

final class ModelLoadingNoteTests: XCTestCase {
    private func run(_ transcriber: SlowModelTranscriber, checkLanguage: Bool) async throws -> [ImportProgress] {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mln-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appending(path: "v.mov")
        try await FixtureVideo.make(at: source, seconds: 1)
        let env = try LangEnvironment(
            root: dir.appending(path: "c"), defaults: UserDefaults(suiteName: "mln-\(UUID().uuidString)")!,
            transcriber: transcriber, dictionaries: TestDictionaries.store(["es": [("casa", nil, "house")], "ja": [("家", "いえ", "house")]]))
        final class Log: @unchecked Sendable { var items: [ImportProgress] = []; let lock = NSLock()
            func add(_ p: ImportProgress) { lock.lock(); items.append(p); lock.unlock() } }
        let log = Log()
        _ = try await env.pipeline.importVideo(from: source, profile: SpanishProfile(), checkLanguage: checkLanguage, progress: { log.add($0) })
        return log.items
    }

    func testLoadingTheModelIsSaidOnTheLanguageCheckAndThenCleared() async throws {
        let transcriber = SlowModelTranscriber()
        let seen = try await run(transcriber, checkLanguage: true)
        let notes = seen.filter { $0.note == .loadingModel }
        XCTAssertEqual(notes.map(\.stage), [.detectingLanguage], "said once, on the step that waits for it")
        let noteIndex = try XCTUnwrap(seen.firstIndex { $0.note == .loadingModel })
        XCTAssertNil(seen[noteIndex + 1].note, "and the very next report clears it")
        XCTAssertEqual(seen[noteIndex + 1].stage, .detectingLanguage)
        let loads = await transcriber.loadCount
        XCTAssertEqual(loads, 1)
    }

    func testWithoutALanguageCheckTheNoteIsOnTranscribing() async throws {
        let seen = try await run(SlowModelTranscriber(), checkLanguage: false)
        XCTAssertEqual(seen.filter { $0.note == .loadingModel }.map(\.stage), [.transcribing])
        XCTAssertFalse(seen.contains { $0.stage == .detectingLanguage })
    }

    func testAModelThatIsAlreadyLoadedSaysNothing() async throws {
        let transcriber = SlowModelTranscriber(preloaded: true)
        let seen = try await run(transcriber, checkLanguage: true)
        XCTAssertFalse(seen.contains { $0.note != nil }, "no note, so no flash of one")
        let loads = await transcriber.loadCount
        XCTAssertEqual(loads, 0)
    }

    @MainActor
    func testTheQueueShowsTheNoteWhileLoadingAndNotAfter() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mlq-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appending(path: "v.mov")
        try await FixtureVideo.make(at: source, seconds: 1)
        let env = try LangEnvironment(
            root: dir.appending(path: "c"), defaults: UserDefaults(suiteName: "mlq-\(UUID().uuidString)")!,
            transcriber: SlowModelTranscriber(), dictionaries: TestDictionaries.store(["es": [("casa", nil, "house")], "ja": [("家", "いえ", "house")]]))
        let queue = ImportQueue(pipeline: env.pipeline)
        queue.enqueue([source], profile: SpanishProfile(), model: SpanishProfile().defaultModel)

        var sawNote = false
        for _ in 0..<400 where !sawNote {
            if queue.jobs.first?.note == .loadingModel { sawNote = true; XCTAssertNotNil(queue.jobs.first?.stageStartedAt) }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(sawNote, "the queue passes the note on while the model loads")
        await queue.waitUntilIdle()
        XCTAssertNil(queue.jobs.first?.note, "and it is gone once the import is done")
        XCTAssertEqual(queue.jobs.first?.status, .imported)
    }
}
