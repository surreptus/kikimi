import XCTest
@testable import LangCore

/// Blocks in transcription until cancelled (or, after the first call, behaves normally when `blockOnlyFirst`).
struct SlowTranscriber: Transcriber {
    var onStart: @Sendable () -> Void = {}
    var calls: LockedBox<Int> = LockedBox(0)
    var blockOnlyFirst = false

    func transcribe(
        mediaURL: URL, whisperCode: String, model: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        onStart()
        let call = calls.mutateReturning { $0 += 1; return $0 }
        if blockOnlyFirst && call > 1 { return spanishSegments }
        try await Task.sleep(for: .seconds(60))   // throws CancellationError as soon as the task is cancelled
        return spanishSegments
    }
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    XCTFail("timed out waiting")
}

final class CancelImportPipelineTests: XCTestCase {
    private let spanish = SpanishProfile()

    func testCancellingDuringTranscriptionStopsCleanlyAndLeavesNothing() async throws {
        let h = try await ImportHarness()
        let started = LockedBox(false)
        let pipeline = h.pipeline(transcriber: StubTranscriber(result: .success([])) )
        _ = pipeline
        let slow = ImportPipeline(
            database: h.database, root: h.container,
            transcriber: SlowTranscriber(onStart: { started.mutate { $0 = true } }))
        let task = Task { try await slow.importVideo(from: h.original, profile: spanish, checkLanguage: false) }
        try await waitUntil { started.value }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected a cancellation")
        } catch is CancellationError {}
        catch { XCTFail("a cancel must not be reported as a failure: \(error)") }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testCancellingDuringTheVideoStepStopsCleanly() async throws {
        let h = try await ImportHarness()
        let started = LockedBox(false)
        let transcoder = StubTranscoder(hevc: { _, _ in
            started.mutate { $0 = true }
            try await Task.sleep(for: .seconds(60))
        })
        let pipeline = h.pipeline(transcoder: transcoder)
        let task = Task { try await pipeline.importVideo(from: h.original, profile: spanish, checkLanguage: false) }
        try await waitUntil { started.value }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected a cancellation")
        } catch is CancellationError {}
        catch { XCTFail("a cancel must not be reported as a failure: \(error)") }
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testACancelledFileCanBeImportedAgain() async throws {
        let h = try await ImportHarness()
        let started = LockedBox(false)
        let slow = ImportPipeline(
            database: h.database, root: h.container,
            transcriber: SlowTranscriber(onStart: { started.mutate { $0 = true } }, blockOnlyFirst: true))
        let task = Task { try await slow.importVideo(from: h.original, profile: spanish, checkLanguage: false) }
        try await waitUntil { started.value }
        task.cancel()
        _ = try? await task.value

        let video = try await slow.importVideo(from: h.original, profile: spanish, checkLanguage: false)
        XCTAssertNotNil(video.id, "the in-flight lock was released and nothing half-finished blocks a retry")
        try h.assertOriginalUntouched()
    }
}

@MainActor
final class CancelImportQueueTests: XCTestCase {
    private func harness(blockOnlyFirst: Bool = false) async throws -> (ImportHarness, ImportQueue, LockedBox<Bool>) {
        let h = try await ImportHarness()
        let started = LockedBox(false)
        let pipeline = ImportPipeline(
            database: h.database, root: h.container,
            transcriber: SlowTranscriber(onStart: { started.mutate { $0 = true } }, blockOnlyFirst: blockOnlyFirst))
        return (h, ImportQueue(pipeline: pipeline), started)
    }

    func testCancellingAWaitingJobAndTheRunningOne() async throws {
        let (h, queue, started) = try await harness()
        let second = h.dir.appending(path: "originals/second.mov")
        try await FixtureVideo.make(at: second, seconds: 3)
        queue.enqueue([h.original, second], profile: SpanishProfile(), model: "m")
        try await waitUntil { started.value }

        queue.cancel(queue.jobs[1].id)
        XCTAssertEqual(queue.jobs[1].status, .cancelled, "a waiting job is cancelled at once")

        queue.cancel(queue.jobs[0].id)
        XCTAssertEqual(queue.jobs[0].status, .cancelling)
        await queue.waitUntilIdle()

        XCTAssertEqual(queue.jobs.map(\.status), [.cancelled, .cancelled])
        XCTAssertFalse(queue.isBusy)
        try h.assertOriginalUntouched()
        try await h.assertNothingLeft()
    }

    func testQueueKeepsWorkingAfterACancel() async throws {
        let (h, queue, started) = try await harness(blockOnlyFirst: true)
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        try await waitUntil { started.value }
        queue.cancel(queue.jobs[0].id)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs[0].status, .cancelled)

        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs[1].status, .imported)

        queue.clearFinished()
        XCTAssertTrue(queue.jobs.isEmpty, "cancelled jobs can be cleared like any finished one")
    }

    func testCancelOnFinishedOrUnknownJobsDoesNothing() async throws {
        let h = try await ImportHarness()
        let queue = ImportQueue(pipeline: h.pipeline())   // a normal, fast import
        queue.enqueue([h.original], profile: SpanishProfile(), model: "m")
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs[0].status, .imported)

        queue.cancel(UUID())                  // unknown id
        queue.cancel(queue.jobs[0].id)        // already finished
        XCTAssertEqual(queue.jobs[0].status, .imported, "a finished job stays as it was")
    }
}
