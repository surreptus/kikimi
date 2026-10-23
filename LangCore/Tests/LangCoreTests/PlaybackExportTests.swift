import AVFoundation
import GRDB
import XCTest
@testable import LangCore

final class SubtitleTimelineTests: XCTestCase {
    private func line(_ start: Double, _ end: Double) -> Subtitle {
        Subtitle(videoId: 1, idx: 0, startTime: start, endTime: end, text: "")
    }

    func testActiveLineFollowsTime() {
        let t = SubtitleTimeline([line(2, 3), line(5, 6)], grace: 1)
        XCTAssertNil(t.index(at: 0), "before the first line")
        XCTAssertNil(t.index(at: 1.99))
        XCTAssertEqual(t.index(at: 2), 0, "start is inclusive")
        XCTAssertEqual(t.index(at: 2.5), 0)
        XCTAssertEqual(t.index(at: 3.8), 0, "stays highlighted during the grace period")
        XCTAssertNil(t.index(at: 4.5), "quiet gap")
        XCTAssertEqual(t.index(at: 5), 1)
        XCTAssertEqual(t.index(at: 6.9), 1)
        XCTAssertNil(t.index(at: 7.5), "after the last line")
    }

    func testUnsortedInputAndEmpty() {
        let t = SubtitleTimeline([line(5, 6), line(2, 3)])
        XCTAssertEqual(t.lines.map(\.startTime), [2, 5])
        XCTAssertNil(SubtitleTimeline([]).index(at: 1))
    }
}

@MainActor
final class PlaybackExportTests: XCTestCase {
    private let segments = [
        TranscriptSegment(start: 0, end: 1.5, text: "La casa es grande."),
        TranscriptSegment(start: 2, end: 3.5, text: "Corremos a la casa."),
        TranscriptSegment(start: 4, end: 5.5, text: "Hola amigos."),
    ]

    /// A 6 s library video imported through the real pipeline (stub transcript, real transcoding).
    private func importedEnvironment() async throws -> (LangEnvironment, Video, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appending(path: "clip.mov")
        try await FixtureVideo.make(at: source, seconds: 6)
        let defaults = UserDefaults(suiteName: "pb-\(UUID().uuidString)")!
        let env = try LangEnvironment(
            root: dir.appending(path: "container"), defaults: defaults,
            transcriber: StubTranscriber(result: .success(segments)))
        let video = try await env.pipeline.importVideo(from: source, profile: SpanishProfile())
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (env, video, dir)
    }

    private func info(_ url: URL) async throws -> (seconds: Double, video: Int, audio: Int) {
        let asset = AVURLAsset(url: url)
        return (try await asset.load(.duration).seconds,
                try await asset.loadTracks(withMediaType: .video).count,
                try await asset.loadTracks(withMediaType: .audio).count)
    }

    // MARK: Playback

    func testSeekingToLinesSyncsActiveLine() async throws {
        let (env, video, _) = try await importedEnvironment()
        let controller = try await env.playback(for: video)
        controller.player.isMuted = true   // the fixture's audio is a 440 Hz tone; keep test runs silent
        defer { controller.stop() }
        XCTAssertEqual(controller.lines.map(\.text), segments.map(\.text))

        await controller.seek(toLine: 1, play: false)
        XCTAssertEqual(controller.activeIndex, 1)
        XCTAssertEqual(controller.player.currentTime().seconds, 2, accuracy: 0.1)

        await controller.nextLine()
        XCTAssertEqual(controller.activeIndex, 2)
        XCTAssertTrue(controller.isPlaying, "stepping to a line plays it, like clicking it")
        controller.pause()
        await controller.nextLine()
        XCTAssertEqual(controller.activeIndex, 2, "stays on the last line")
        await controller.previousLine()
        await controller.previousLine()
        await controller.previousLine()
        XCTAssertEqual(controller.activeIndex, 0, "stays on the first line")
        controller.pause()

        await controller.seek(to: 4.8, play: false)
        XCTAssertEqual(controller.activeIndex, 2)
        await controller.seek(to: 3.9, play: false)
        XCTAssertEqual(controller.activeIndex, 1, "in the gap, within grace of line 2")
        XCTAssertFalse(controller.isPlaying)
    }

    func testPlayingAdvancesTheActiveLine() async throws {
        let (env, video, _) = try await importedEnvironment()
        let controller = try await env.playback(for: video)
        controller.player.isMuted = true   // the fixture's audio is a 440 Hz tone; keep test runs silent
        defer { controller.stop() }
        await controller.seek(toLine: 0, play: true)
        XCTAssertTrue(controller.isPlaying)

        var advanced = false
        for _ in 0..<60 {   // up to ~6 s for playback to reach line 1 at t = 2
            try await Task.sleep(for: .milliseconds(100))
            if controller.activeIndex == 1 { advanced = true; break }
        }
        XCTAssertTrue(advanced, "active line should follow playback; at \(controller.currentTime)s index \(String(describing: controller.activeIndex))")
    }

    // MARK: Clips

    func testAudioClipHasRequestedLengthAndOnlyAudio() async throws {
        let (env, video, dir) = try await importedEnvironment()
        let out = dir.appending(path: "line2.m4a")
        try await env.clips.export(video: video, start: 2, end: 3.5, kind: .audio, to: out)
        let clip = try await info(out)
        XCTAssertEqual(clip.seconds, 1.8, accuracy: 0.15)   // 1.5 s + 0.15 s padding each side
        XCTAssertEqual(clip.audio, 1)
        XCTAssertEqual(clip.video, 0)
    }

    func testVideoClipHasPictureAndSound() async throws {
        let (env, video, dir) = try await importedEnvironment()
        let out = dir.appending(path: "line2.mp4")
        try await env.clips.export(video: video, start: 2, end: 3.5, kind: .video, to: out)
        let clip = try await info(out)
        XCTAssertEqual(clip.seconds, 1.8, accuracy: 0.25)
        XCTAssertEqual(clip.video, 1)
        XCTAssertEqual(clip.audio, 1)
    }

    func testClipsAreClampedToTheMedia() async throws {
        let (env, video, dir) = try await importedEnvironment()
        let out = dir.appending(path: "edge.m4a")
        try await env.clips.export(video: video, start: 0, end: 1.5, kind: .audio, padding: 1, to: out)
        let clip = try await info(out)
        XCTAssertEqual(clip.seconds, 2.5, accuracy: 0.15, "no negative start")

        try await env.clips.export(video: video, start: 5, end: 99, kind: .audio, to: out)
        let tail = try await info(out)
        XCTAssertLessThanOrEqual(tail.seconds, 1.3, "no overrun past the end")
    }

    func testBadRangesAndMissingSourcesFail() async throws {
        let (env, video, dir) = try await importedEnvironment()
        let out = dir.appending(path: "bad.m4a")
        do {
            try await env.clips.export(video: video, start: 50, end: 60, kind: .audio, padding: 0, to: out)
            XCTFail("expected emptyRange")
        } catch ClipError.emptyRange {}

        var ghost = video
        ghost.audioPath = "nope/audio.m4a"
        do {
            try await env.clips.export(video: ghost, start: 0, end: 1, kind: .audio, to: out)
            XCTFail("expected missingSource")
        } catch ClipError.missingSource {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testExportingAWordsExamples() async throws {
        let (env, _, dir) = try await importedEnvironment()
        let casa = try await env.database.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)! }
        let folder = dir.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let first = try await env.exportClips(forWord: casa.id!, kind: .audio, into: folder)
        XCTAssertEqual(first.map(\.lastPathComponent), ["casa-1.m4a", "casa-2.m4a"], "one per line containing the word")
        let second = try await env.exportClips(forWord: casa.id!, kind: .audio, into: folder)
        XCTAssertEqual(second.map(\.lastPathComponent), ["casa-1 2.m4a", "casa-2 2.m4a"], "never overwrites earlier exports")
        for url in first {
            let clip = try await info(url)
            XCTAssertGreaterThan(clip.seconds, 1)
        }
        let all = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(all.count, 4)
    }

    func testFileNamesAreSanitized() {
        XCTAssertEqual(ClipExporter.sanitized("a/b:c?"), "a-b-c-")
        XCTAssertEqual(ClipExporter.sanitized("  ..hidden"), "hidden")
        XCTAssertEqual(ClipExporter.sanitized(""), "clip")
        XCTAssertEqual(ClipExporter.sanitized("食べる"), "食べる")
        XCTAssertEqual(ClipExporter.sanitized(String(repeating: "x", count: 200)).count, 60)
    }
}
