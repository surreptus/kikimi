import XCTest
@testable import LangCore

@MainActor
final class ImportQueueTests: XCTestCase {
    func testImportsSequentiallyAndReportsDuplicates() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline())
        let copy = h.dir.appending(path: "originals/same bytes.mov")
        try FileManager.default.copyItem(at: h.original, to: copy)

        queue.enqueue([h.original, copy], profile: SpanishProfile(), model: "m")
        XCTAssertTrue(queue.isBusy)
        await queue.waitUntilIdle()

        XCTAssertEqual(queue.jobs.map(\.status), [.imported, .duplicate])
        XCTAssertFalse(queue.isBusy)
        try h.assertOriginalUntouched()
        let count = try await h.database.libraryVideos().count
        XCTAssertEqual(count, 1)
    }

    func testFailureIsReportedAndQueueContinues() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline(transcriber: StubTranscriber(result: .failure(ModelError.notInstalled("m")))))
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()

        guard case .failed(let message) = queue.jobs[0].status else { return XCTFail("expected failure") }
        XCTAssertEqual(message, "The speech model isn't downloaded yet.")
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()

        queue.clearFinished()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testMissingFileFailsCleanly() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline())
        queue.enqueue([h.dir.appending(path: "nope.mov")], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        guard case .failed = queue.jobs[0].status else { return XCTFail("expected failure") }
        XCTAssertFalse(queue.isBusy)
    }

    func testCanEnqueueAgainAfterIdle() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline())
        queue.enqueue([h.dir.appending(path: "nope.mov")], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs.last?.status, .imported)
    }
}

final class TranscriptCleanerTests: XCTestCase {
    private func seg(_ start: Double, _ end: Double, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    func testDropsSoundTagsAndKeepsSpeech() {
        let cleaned = TranscriptCleaner.clean([
            seg(0, 3, "Hola, ¿cómo estás?"),
            seg(3, 13, "[AUDIO_EN_BLANCO]"),
            seg(13, 15, "[BLANK_AUDIO]"),
            seg(15, 17, "(música)"),
            seg(17, 19, "♪♪"),
            seg(19, 20, "   "),
            seg(20, 21, "..."),
        ])
        XCTAssertEqual(cleaned.map(\.text), ["Hola, ¿cómo estás?"])
    }

    func testStripsTagsInsideSpeechAndTidiesSpaces() {
        let cleaned = TranscriptCleaner.clean([seg(0, 2, "[MÚSICA]  Buenas   noches (risas) a todos ♪")])
        XCTAssertEqual(cleaned.map(\.text), ["Buenas noches a todos"])
    }

    func testClampsToAudioLengthAndDropsSegmentsBeyondIt() {
        let cleaned = TranscriptCleaner.clean(
            [seg(60, 75, "Hasta luego"), seg(73, 80, "Fuera del audio"), seg(-1, 2, "Primero")], audioDuration: 73)
        XCTAssertEqual(cleaned, [seg(60, 73, "Hasta luego"), seg(0, 2, "Primero")])
    }

    func testKeepsNonLatinSpeechAndNumbers() {
        let cleaned = TranscriptCleaner.clean([seg(0, 2, "昨日は友達と行きました。"), seg(2, 3, "2024")])
        XCTAssertEqual(cleaned.count, 2)
    }

    /// The exact non-speech lines Whisper medium produced for a real Spanish vlog.
    func testRealWorldTagsFromARecording() {
        let input = [
            seg(0, 5, "Algo raro está pasando aquí y quiero saber qué está pasando."),
            seg(71.5, 99, "[Música]"), seg(173.7, 177.8, "[SONIDO]"), seg(326.9, 329.9, "(Suspiro)"),
            seg(203.5, 214.9, "[Música]"), seg(512.3, 514.3, "¡Sana!"), seg(142.7, 144.7, "- ¿Solo calvo? - Sí."),
        ]
        XCTAssertEqual(TranscriptCleaner.clean(input).map(\.text),
                       ["Algo raro está pasando aquí y quiero saber qué está pasando.", "¡Sana!", "- ¿Solo calvo? - Sí."])
    }

    func testNothingToDoIsANoOp() {
        let input = [seg(0, 1, "Uno"), seg(1, 2, "Dos")]
        XCTAssertEqual(TranscriptCleaner.clean(input), input)
        XCTAssertEqual(TranscriptCleaner.clean([]), [])
    }
}
