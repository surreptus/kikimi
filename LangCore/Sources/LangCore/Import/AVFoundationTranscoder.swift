// How this file works, in the order you need it:
//
// 1. `VideoPlan.plan(for:)` is pure arithmetic: given the source's codec, size and bitrate, it decides
//    "keep as is" or "re-encode to HEVC at this size and bitrate". It is the only part with tuning knobs.
// 2. `AVFoundationTranscoder.compact` carries out that plan. Pass-through, and the audio export, use
//    `AVAssetExportSession` (`export`). A re-encode needs a chosen size and bitrate, which the export
//    session can't do, so it uses `AVAssetReader` and `AVAssetWriter` (`reencode`).
// 3. If the re-encoded file isn't smaller than the source, `compact` swaps in a copy of the original streams.
// 4. `MediaVerifier` checks the result before the import pipeline keeps it.
//
// The reader/writer path is the hard part. `pump` copies samples from a reader output into a writer input on
// AVFoundation's own queue, and the two pumps (video, audio) run concurrently. Cancelling is where it bites:
// AVAssetWriterInput raises an uncaught exception if it is touched after `cancelWriting()`, and after that call
// AVFoundation never invokes the "ready for more data" block again, so anything waiting on it would hang.
// `Gate` solves both: every writer call goes through it under a lock, and cancelling wakes the waiters.
// A cancel only resumes the caller once no pump is mid-call (`Gate.whenIdle`), so the reader and writer are never
// freed under a running pump; that ordering is what a rare crash under load came from.
// `Once` makes sure each pump's continuation is resumed exactly one time, whichever of "finished" or
// "cancelled" happens first. The `nonisolated(unsafe)` lets are safe for the same reason: the gate, not the
// compiler, guarantees one thread touches an AVFoundation object at a time.

import AVFoundation
import Foundation

public enum TranscodeError: Error, LocalizedError {
    case presetUnavailable(String)
    case noVideoTrack
    case readerFailed(Error?)
    case writerFailed(Error?)

    public var errorDescription: String? {
        switch self {
        case .presetUnavailable(let preset): "This Mac can't export with \(preset)."
        case .noVideoTrack: "This file has no video track."
        case .readerFailed(let e): "Couldn't read the video: \(e?.localizedDescription ?? "unknown error")"
        case .writerFailed(let e): "Couldn't write the video: \(e?.localizedDescription ?? "unknown error")"
        }
    }
}

/// How the library copy of a video is made. The copy is for reference, so size matters more than quality:
/// small HEVC is kept as is, everything else becomes low-bitrate HEVC at no more than 480 px on the short side.
public enum VideoPlan: Equatable, Sendable {
    case passThrough
    case reencode(width: Int, height: Int, bitrate: Int)

    public struct Source: Sendable {
        public var isHEVC: Bool
        public var width: Int
        public var height: Int
        public var frameRate: Double
        /// Video bits per second; 0 if unknown.
        public var bitrate: Double

        public init(isHEVC: Bool, width: Int, height: Int, frameRate: Double, bitrate: Double) {
            self.isHEVC = isHEVC; self.width = width; self.height = height
            self.frameRate = frameRate; self.bitrate = bitrate
        }
    }

    // Tuning knobs for "good enough to follow along".
    public static let shortSideLimit = 480.0
    public static let bitsPerPixelPerFrame = 0.05
    public static let bitrateFraction = 0.5      // of the source's, when that is lower than the budget
    public static let minimumBitrate = 100_000.0
    /// An HEVC source up to this multiple of the budget is kept untouched.
    public static let hevcTolerance = 1.25

    public static func plan(for source: Source) -> VideoPlan {
        let scale = min(1, shortSideLimit / Double(max(1, min(source.width, source.height))))
        let width = even(Double(source.width) * scale), height = even(Double(source.height) * scale)
        let fps = source.frameRate > 0 ? source.frameRate : 30
        let budget = max(minimumBitrate, bitsPerPixelPerFrame * Double(width * height) * fps)

        if source.isHEVC, source.bitrate > 0, source.bitrate <= budget * hevcTolerance { return .passThrough }

        var target = source.bitrate > 0 ? min(source.bitrate * bitrateFraction, budget) : budget
        if source.bitrate > 0 { target = min(target, source.bitrate * 0.9) }
        return .reencode(width: width, height: height, bitrate: Int(max(minimumBitrate * (source.bitrate > 0 && source.bitrate < minimumBitrate ? 0.5 : 1), target)))
    }

    private static func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
}

/// Makes the library copy of a video (HEVC, see `VideoPlan`) and the AAC audio export.
public struct AVFoundationTranscoder: MediaTranscoder {
    public enum Method: Equatable, Sendable {
        case passedThrough        // source streams copied unchanged
        case reencoded            // new low-bitrate HEVC
        case keptOriginalStreams  // re-encoding wasn't smaller, so the source streams were copied instead
    }

    public init() {}

    public func compactVideo(
        source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await compact(source: source, destination: destination, progress: progress)
    }

    public func extractAAC(source: URL, destination: URL) async throws {
        try await export(source: source, preset: AVAssetExportPresetAppleM4A,
                         type: .m4a, destination: destination, progress: { _ in })
    }

    /// Like `compactVideo`, but reports what it did.
    @discardableResult
    public func compact(
        source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Method {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw TranscodeError.noVideoTrack }

        let (size, fps, rate, formats) = try await video.load(.naturalSize, .nominalFrameRate, .estimatedDataRate, .formatDescriptions)
        let duration = try await asset.load(.duration).seconds
        let sourceBytes = Self.fileSize(source)
        var bitrate = Double(rate)
        if bitrate <= 0, duration > 0 {   // some containers don't say; derive it from the file
            let audioRate = try await asset.loadTracks(withMediaType: .audio).first?.load(.estimatedDataRate) ?? 0
            bitrate = max(0, Double(sourceBytes) * 8 / duration - Double(audioRate))
        }
        let info = VideoPlan.Source(
            isHEVC: formats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC } ?? false,
            width: Int(abs(size.width)), height: Int(abs(size.height)), frameRate: Double(fps), bitrate: bitrate)

        guard case .reencode(let width, let height, let target) = VideoPlan.plan(for: info) else {
            try await export(source: source, preset: AVAssetExportPresetPassthrough, type: .mov,
                             destination: destination, progress: progress)
            return .passedThrough
        }

        try await reencode(asset: asset, video: video, to: destination, width: width, height: height,
                           bitrate: target, duration: duration, progress: progress)
        if Self.fileSize(destination) < sourceBytes { return .reencoded }

        // Not smaller than what we were given: keep the original streams, unless they can't be copied.
        let copy = destination.deletingLastPathComponent().appending(path: "passthrough-\(UUID().uuidString).mov")
        do {
            try await export(source: source, preset: AVAssetExportPresetPassthrough, type: .mov,
                             destination: copy, progress: { _ in })
            try FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: copy, to: destination)
            return .keptOriginalStreams
        } catch {
            try? FileManager.default.removeItem(at: copy)
            return .reencoded   // a larger but valid file beats a failed import
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Export-session path (passthrough, audio)

    private func export(
        source: URL, preset: String, type: AVFileType, destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TranscodeError.presetUnavailable(preset)
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: type)
    }

    // MARK: Reader/writer path (HEVC at a chosen size and bitrate)

    /// Serialises cancellation with every call into the writer: AVAssetWriterInput raises an uncaught exception if
    /// it is used after `cancelWriting()`, which would take the whole app down.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var wakeups: [() -> Void] = []
        /// How many pump blocks are currently inside the reader or writer, and what is waiting for them to leave.
        private var running = 0
        private var idleWaiters: [() -> Void] = []

        /// Cancels once: runs `body` (the AVFoundation cancel calls), then wakes everything waiting on the writer,
        /// because after `cancelWriting()` AVFoundation never calls the "ready for more data" blocks again.
        func cancel(_ body: () -> Void) {
            lock.lock()
            guard !cancelled else { lock.unlock(); return }
            cancelled = true
            body()
            let pending = wakeups
            wakeups = []
            lock.unlock()
            pending.forEach { $0() }
        }

        /// Runs `body` only if not cancelled; returns whether it ran.
        @discardableResult func ifOpen(_ body: () -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { return false }
            body()
            return true
        }

        /// Like `ifOpen`, and remembers `wakeup` to call if a cancel arrives later.
        func registerIfOpen(_ body: () -> Void, wakeup: @escaping () -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { return false }
            body()
            wakeups.append(wakeup)
            return true
        }

        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

        /// A pump block calls this before it touches the reader or writer. False means cancelled: do nothing.
        func enterBlock() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { return false }
            running += 1
            return true
        }

        func exitBlock() {
            lock.lock()
            running -= 1
            let ready = running == 0 ? idleWaiters : []
            if running == 0 { idleWaiters = [] }
            lock.unlock()
            ready.forEach { $0() }
        }

        /// Runs `body` once no pump block is inside the reader or writer. Resuming the transcode earlier would let
        /// it return and free them while a block is still in `copyNextSampleBuffer`, which crashes.
        func whenIdle(_ body: @escaping () -> Void) {
            lock.lock()
            if running == 0 { lock.unlock(); body() } else { idleWaiters.append(body); lock.unlock() }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) { lock.lock(); defer { lock.unlock() }; if !done { done = true; body() } }
    }

    private func reencode(
        asset: AVURLAsset, video: AVAssetTrack, to destination: URL, width: Int, height: Int, bitrate: Int,
        duration: Double, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (transform, start) = try await video.load(.preferredTransform, .timeRange)
        let audio = try await asset.loadTracks(withMediaType: .audio).first

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(videoOut)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        videoIn.transform = transform
        writer.add(videoIn)

        var audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        if let audio {
            let formats = try await audio.load(.formatDescriptions)
            if let format = formats.first, CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC {
                // AAC is copied as is: no second round of lossy compression.
                audioPair = (AVAssetReaderTrackOutput(track: audio, outputSettings: nil),
                             AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format))
            } else {
                let asbd = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                let channels = min(2, max(1, Int(asbd?.mChannelsPerFrame ?? 2)))
                let rate = (asbd?.mSampleRate).flatMap { $0 > 0 ? $0 : nil } ?? 44_100
                audioPair = (
                    AVAssetReaderTrackOutput(track: audio, outputSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: channels, AVSampleRateKey: rate]),
                    AVAssetWriterInput(mediaType: .audio, outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: channels,
                        AVSampleRateKey: rate, AVEncoderBitRateKey: 64_000 * channels]))
            }
            reader.add(audioPair!.0)
            writer.add(audioPair!.1)
        }

        guard reader.startReading() else { throw TranscodeError.readerFailed(reader.error) }
        guard writer.startWriting() else { throw TranscodeError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: start.start)

        nonisolated(unsafe) let videoOutput = videoOut, videoInput = videoIn
        nonisolated(unsafe) let audioPairU = audioPair
        let gate = Gate()
        await withTaskCancellationHandler {
            async let v: Void = Self.pump(videoOutput, into: videoInput, label: "video", gate: gate) { sample in
                if duration > 0 {
                    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    progress(max(0, min(1, t / duration)))
                }
            }
            async let a: Void = Self.pumpAudio(audioPairU, gate: gate)
            _ = await (v, a)
        } onCancel: {
            gate.cancel {
                reader.cancelReading()
                writer.cancelWriting()
            }
        }

        if gate.isCancelled || Task.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        if reader.status == .failed { writer.cancelWriting(); throw TranscodeError.readerFailed(reader.error) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw TranscodeError.writerFailed(writer.error) }
    }

    private static func pumpAudio(_ pair: (AVAssetReaderOutput, AVAssetWriterInput)?, gate: Gate) async {
        guard let pair else { return }
        await pump(pair.0, into: pair.1, label: "audio", gate: gate, onSample: nil)
    }

    private static func pump(
        _ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String, gate: Gate,
        onSample: (@Sendable (CMSampleBuffer) -> Void)?
    ) async {
        let once = Once()
        nonisolated(unsafe) let output = output, input = input
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let registered = gate.registerIfOpen({
                input.requestMediaDataWhenReady(on: DispatchQueue(label: "transcode.\(label)")) {
                    guard gate.enterBlock() else { return }   // cancelled; the wakeup below resumes the caller
                    defer { gate.exitBlock() }
                    while input.isReadyForMoreMediaData {
                        var finished = gate.isCancelled
                        if !finished {
                            if let sample = output.copyNextSampleBuffer() {
                                var appended = false
                                gate.ifOpen { appended = input.append(sample) }
                                if appended { onSample?(sample) } else { finished = true }
                            } else {
                                finished = true
                            }
                        }
                        if finished {
                            once.run {
                                gate.ifOpen { input.markAsFinished() }
                                done.resume()
                            }
                            return
                        }
                    }
                }
            }, wakeup: { gate.whenIdle { once.run { done.resume() } } })
            if !registered { once.run { done.resume() } }
        }
    }
}

public enum MediaVerifier {
    public static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// Checks that `output` opens as an AVAsset, has a video track, and matches the source duration.
    public static func verify(output: URL, expectedDuration: Double) async throws {
        let asset = AVURLAsset(url: output)
        do {
            guard try await asset.load(.isPlayable) else {
                throw ImportError.verificationFailed("output is not playable")
            }
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                throw ImportError.verificationFailed("output has no video track")
            }
            let actual = try await asset.load(.duration).seconds
            let tolerance = max(0.5, expectedDuration * 0.01)
            guard abs(actual - expectedDuration) <= tolerance else {
                throw ImportError.verificationFailed(
                    "duration \(actual)s differs from source \(expectedDuration)s")
            }
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.verificationFailed("output could not be opened: \(error)")
        }
    }
}
