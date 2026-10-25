import AVFoundation
import XCTest
@testable import LangCore

final class VideoPlanTests: XCTestCase {
    private func plan(hevc: Bool, _ w: Int, _ h: Int, fps: Double = 30, kbps: Double) -> VideoPlan {
        VideoPlan.plan(for: .init(isHEVC: hevc, width: w, height: h, frameRate: fps, bitrate: kbps * 1000))
    }

    func testSmallHEVCIsKeptUntouched() {
        XCTAssertEqual(plan(hevc: true, 640, 360, kbps: 150), .passThrough)
    }

    func testLargeHEVCIsShrunkLikeAnythingElse() {
        // A phone recording: HEVC, but 1080p at 10 Mbps. Keeping it would defeat the point.
        XCTAssertEqual(plan(hevc: true, 1920, 1080, kbps: 10_000), .reencode(width: 854, height: 480, bitrate: 614_880))
    }

    func testLowBitrateH264GetsHalfItsBitrate() {
        XCTAssertEqual(plan(hevc: false, 640, 360, kbps: 460), .reencode(width: 640, height: 360, bitrate: 230_000))
    }

    func testHighBitrateSourcesAreCappedByTheBudgetAndScaledDown() {
        XCTAssertEqual(plan(hevc: false, 1920, 1080, kbps: 8_000), .reencode(width: 854, height: 480, bitrate: 614_880))
    }

    func testNeverUpscalesAndKeepsDimensionsEven() {
        XCTAssertEqual(plan(hevc: false, 320, 240, kbps: 300), .reencode(width: 320, height: 240, bitrate: 115_200),
                       "half of 300 would be 150 kbps, but the size budget for 320x240 is 115.2 kbps")
        guard case .reencode(let w, let h, _) = plan(hevc: false, 641, 361, kbps: 900) else { return XCTFail() }
        XCTAssertEqual(w % 2, 0)
        XCTAssertEqual(h % 2, 0)
    }

    func testPortraitVideoLimitsTheShortSide() {
        XCTAssertEqual(plan(hevc: false, 1080, 1920, kbps: 8_000), .reencode(width: 480, height: 854, bitrate: 614_880))
    }

    func testUnknownBitrateUsesTheBudget() {
        XCTAssertEqual(plan(hevc: false, 1280, 720, kbps: 0), .reencode(width: 854, height: 480, bitrate: 614_880))
        // Unknown bitrate can't prove an HEVC file is small, so it is re-encoded.
        XCTAssertNotEqual(plan(hevc: true, 640, 360, kbps: 0), .passThrough)
    }

    func testTargetIsAlwaysBelowTheSourceBitrate() {
        for kbps in [60.0, 80, 150, 300, 460, 900, 2_000, 8_000] {
            guard case .reencode(_, _, let target) = plan(hevc: false, 640, 360, kbps: kbps) else { return XCTFail() }
            XCTAssertLessThan(Double(target), kbps * 1000, "\(kbps) kbps")
            XCTAssertGreaterThanOrEqual(target, 50_000)
        }
    }
}

final class AudioPlanTests: XCTestCase {
    func testLoudSourcesAreRecompressedAndSmallOnesCopied() {
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 2, bitrate: 128_000), .reencode(bitrate: 64_000))
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 2, bitrate: 96_000), .copy, "up to 1.5x the target is kept")
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 2, bitrate: 64_000), .copy)
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 1, bitrate: 128_000), .reencode(bitrate: 48_000))
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 1, bitrate: 64_000), .copy)
    }

    func testOtherFormatsAndUnknownRatesAreEncoded() {
        XCTAssertEqual(AudioPlan.plan(isAAC: false, channels: 2, bitrate: 32_000), .reencode(bitrate: 64_000))
        XCTAssertEqual(AudioPlan.plan(isAAC: true, channels: 2, bitrate: 0), .reencode(bitrate: 64_000))
    }
}

final class SmartTranscoderTests: XCTestCase {
    private let transcoder = AVFoundationTranscoder()

    private func scratch() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "smart-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private struct Info {
        var codec: FourCharCode, width: Int, height: Int, seconds: Double, bytes: Int64, audioCodec: FourCharCode?
    }

    private func inspect(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await video.load(.naturalSize)
        let codec = CMFormatDescriptionGetMediaSubType(try await video.load(.formatDescriptions)[0])
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let audioCodec = try await audio?.load(.formatDescriptions).first.map { CMFormatDescriptionGetMediaSubType($0) }
        return Info(codec: codec, width: Int(size.width), height: Int(size.height),
                    seconds: try await asset.load(.duration).seconds,
                    bytes: AVFoundationTranscoder.fileSize(url), audioCodec: audioCodec)
    }

    func testHEVCSourceIsCopiedNotReencoded() async throws {
        let dir = scratch()
        let source = dir.appending(path: "in.mov"), out = dir.appending(path: "out.mov")
        try await FixtureVideo.make(at: source, seconds: 3, codec: .hevc)
        let method = try await transcoder.compact(source: source, destination: out, progress: { _ in })

        XCTAssertEqual(method, .passedThrough)
        let a = try await inspect(source), b = try await inspect(out)
        XCTAssertEqual(b.codec, kCMVideoCodecType_HEVC)
        XCTAssertEqual(b.seconds, a.seconds, accuracy: 0.2)
        XCTAssertLessThanOrEqual(b.bytes, a.bytes + max(8_000, a.bytes / 10), "a copy, not a bigger re-encode")
        XCTAssertEqual(b.audioCodec, kAudioFormatMPEG4AAC)
    }

    func testBusyH264IsReencodedSmallerAsHEVC() async throws {
        let dir = scratch()
        let source = dir.appending(path: "in.mov"), out = dir.appending(path: "out.mov")
        try await FixtureVideo.make(at: source, seconds: 3, size: (640, 360), fps: 15, bitrate: 3_000_000, noise: true)
        let reported = LockedBox<[Double]>([])
        let method = try await transcoder.compact(source: source, destination: out) { p in reported.mutate { $0.append(p) } }

        XCTAssertEqual(method, .reencoded)
        let a = try await inspect(source), b = try await inspect(out)
        XCTAssertEqual(a.codec, kCMVideoCodecType_H264)
        XCTAssertEqual(b.codec, kCMVideoCodecType_HEVC)
        XCTAssertLessThan(b.bytes, a.bytes, "the whole point")
        XCTAssertEqual(b.width, 640)
        XCTAssertEqual(b.height, 360)
        XCTAssertEqual(b.seconds, a.seconds, accuracy: 0.3)
        XCTAssertNotNil(b.audioCodec)
        XCTAssertFalse(reported.value.isEmpty, "progress is reported")
        XCTAssertEqual(reported.value, reported.value.sorted(), "and never goes backwards")
        XCTAssertLessThanOrEqual(reported.value.max() ?? 2, 1)
    }

    func testBigSourcesAreScaledDownToReferenceSize() async throws {
        let dir = scratch()
        let source = dir.appending(path: "in.mov"), out = dir.appending(path: "out.mov")
        try await FixtureVideo.make(at: source, seconds: 3, size: (1280, 720), fps: 15, bitrate: 6_000_000, noise: true)
        try await transcoder.compact(source: source, destination: out, progress: { _ in })

        let a = try await inspect(source), b = try await inspect(out)
        XCTAssertEqual(b.height, 480)
        XCTAssertEqual(b.width, 854)
        XCTAssertLessThan(b.bytes * 4, a.bytes, "much smaller than the source")
        XCTAssertEqual(b.seconds, a.seconds, accuracy: 0.3)
    }

    func testPlainAudioIsEncodedToAAC() async throws {
        let dir = scratch()
        let source = dir.appending(path: "in.mov"), out = dir.appending(path: "out.mov")
        try await FixtureVideo.make(at: source, seconds: 3, size: (640, 360), fps: 15, bitrate: 3_000_000, noise: true, pcmAudio: true)
        let a = try await inspect(source)
        XCTAssertEqual(a.audioCodec, kAudioFormatLinearPCM)
        try await transcoder.compact(source: source, destination: out, progress: { _ in })

        let b = try await inspect(out)
        XCTAssertEqual(b.audioCodec, kAudioFormatMPEG4AAC)
        XCTAssertLessThan(b.bytes, a.bytes)
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio).first!
        let rate = try await track.load(.estimatedDataRate)
        XCTAssertLessThanOrEqual(rate, 64_000 * 1.3, "speech doesn't need more than about 64 kbps")
        // The speech must still be there for transcription.
        let samples = try await AudioExtractor.pcm16kMono(from: out)
        let rms = (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
        XCTAssertGreaterThan(rms, 0.1)
    }

    func testResultIsNeverLargerThanTheSource() async throws {
        // A tiny, near-static clip: re-encoding can't beat it, so the original streams must be kept.
        let dir = scratch()
        let source = dir.appending(path: "in.mov"), out = dir.appending(path: "out.mov")
        try await FixtureVideo.make(at: source, seconds: 2)
        let method = try await transcoder.compact(source: source, destination: out, progress: { _ in })

        let a = try await inspect(source), b = try await inspect(out)
        print("static clip: method \(method), source \(a.bytes) B, output \(b.bytes) B")
        XCTAssertLessThanOrEqual(b.bytes, a.bytes + max(8_000, a.bytes / 10))
        XCTAssertEqual(b.seconds, a.seconds, accuracy: 0.3)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("passthrough-") }
        XCTAssertTrue(leftovers.isEmpty, "temporary copies are cleaned up")
    }

    func testAudioOnlyFilesAreRejectedClearly() async throws {
        let dir = scratch()
        let video = dir.appending(path: "in.mov"), audio = dir.appending(path: "in.m4a")
        try await FixtureVideo.make(at: video, seconds: 2)
        try await FixtureVideo.exportAudioOnly(from: video, to: audio)
        do {
            try await transcoder.compact(source: audio, destination: dir.appending(path: "out.mov"), progress: { _ in })
            XCTFail("expected noVideoTrack")
        } catch TranscodeError.noVideoTrack {
            XCTAssertEqual(TranscodeError.noVideoTrack.errorDescription, "This file has no video track.")
        }
    }

    func testCancellingNeverCrashesAndLeavesNoPartialFile() async throws {
        let dir = scratch()
        let source = dir.appending(path: "in.mov")
        try await FixtureVideo.make(at: source, seconds: 6, size: (1280, 720), fps: 15, bitrate: 6_000_000, noise: true)
        // Cancel at different moments: before it starts, just after, and while frames are being written.
        for (index, delay) in [0, 5, 30, 120].enumerated() {
            let out = dir.appending(path: "out\(index).mov")
            let task = Task { try await transcoder.compact(source: source, destination: out, progress: { _ in }) }
            try await Task.sleep(for: .milliseconds(delay))
            task.cancel()
            do {
                _ = try await task.value
                // It finished before the cancel landed: then it must be a complete, valid file.
                XCTAssertGreaterThan(AVFoundationTranscoder.fileSize(out), 0, "delay \(delay)")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "no partial file after cancel (delay \(delay))")
            }
        }
    }

    /// Runs the real transcoder on any file (LANGCORE_COMPACT_FILE) and reports size and time. Read-only on the input.
    func testReportOnProvidedFile() async throws {
        guard let path = ProcessInfo.processInfo.environment["LANGCORE_COMPACT_FILE"] else { throw XCTSkip("set LANGCORE_COMPACT_FILE") }
        let source = URL(filePath: path), out = scratch().appending(path: "out.mov")
        let a = try await inspect(source)
        let started = Date()
        let method = try await transcoder.compact(source: source, destination: out, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let b = try await inspect(out)
        func mb(_ n: Int64) -> String { String(format: "%.1f MB", Double(n) / 1_048_576) }
        print("COMPACT \(method): \(mb(a.bytes)) -> \(mb(b.bytes)) (\(String(format: "%.0f", Double(b.bytes) / Double(max(1, a.bytes)) * 100))%), \(a.width)x\(a.height) -> \(b.width)x\(b.height), duration \(String(format: "%.1f", a.seconds))s -> \(String(format: "%.1f", b.seconds))s, took \(String(format: "%.1f", seconds))s")
        XCTAssertEqual(b.seconds, a.seconds, accuracy: 0.5)
        XCTAssertLessThanOrEqual(b.bytes, a.bytes + max(8_000, a.bytes / 10))
        try await MediaVerifier.verify(output: out, expectedDuration: a.seconds)
    }
}
