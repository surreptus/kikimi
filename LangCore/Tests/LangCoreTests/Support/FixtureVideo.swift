import AVFoundation
import Foundation

/// Writes a small H.264 + AAC .mov (solid frames, 440 Hz tone) for tests.
enum FixtureVideo {
    /// `speech` replaces the 440 Hz tone with real samples (padded with silence to the video's length).
    /// Other knobs build realistic sources: `codec`, `size`, `fps`, a target `bitrate`, `noise` frames (which can't be
    /// compressed, so the encoder really spends its bitrate), and uncompressed `pcmAudio`.
    static func make(
        at url: URL, seconds: Int = 2, withAudio: Bool = true, speech: (samples: [Float], rate: Int)? = nil,
        codec: AVVideoCodecType = .h264, size: (width: Int, height: Int) = (320, 240), fps: Int = 10,
        bitrate: Int? = nil, noise: Bool = false, pcmAudio: Bool = false
    ) async throws {
        let width = size.width, height = size.height, rate = speech?.rate ?? 44_100
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        var videoSettings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
        if let bitrate { videoSettings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitrate] }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(videoInput)

        let audioSettings: [String: Any] = pcmAudio
            ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
               AVLinearPCMIsNonInterleaved: false]
            : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        if withAudio { writer.add(audioInput) }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Pull model: the writer calls back whenever an input can take more, which avoids interleaving deadlocks.
        let frames = seconds * fps
        async let videoDone: Void = feed(videoInput, count: frames, queue: "fixture.video") { frame in
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            if noise {
                arc4random_buf(CVPixelBufferGetBaseAddress(pixels), CVPixelBufferGetDataSize(pixels))
            } else {
                memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 8 % 256), CVPixelBufferGetDataSize(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        async let audioDone: Void = feed(audioInput, count: withAudio ? frames : 0, queue: "fixture.audio") { frame in
            let n = rate / fps
            let samples: [Float]
            if let speech {
                let start = frame * n
                samples = (0..<n).map { start + $0 < speech.samples.count ? speech.samples[start + $0] : 0 }
            } else {
                samples = (0..<n).map { i in
                    Float(sin(2 * Double.pi * 440 * Double(frame * n + i) / Double(rate))) * 0.5
                }
            }
            audioInput.append(audioBuffer(samples, start: frame * n, rate: rate))
        }
        _ = await (videoDone, audioDone)
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Appends `count` items as the input asks for them, then marks it finished.
    private static func feed(
        _ input: AVAssetWriterInput, count: Int, queue name: String, append: @escaping (Int) -> Void
    ) async {
        guard count > 0 else { return }
        final class Counter: @unchecked Sendable { var next = 0 }
        let counter = Counter()
        let queue = DispatchQueue(label: name)
        nonisolated(unsafe) let input = input
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if counter.next == count {
                        input.markAsFinished()
                        done.resume()
                        return
                    }
                    append(counter.next)
                    counter.next += 1
                }
            }
        }
    }

    private static func audioBuffer(_ samples: [Float], start: Int, rate: Int) -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
            magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let bytes = samples.count * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        samples.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!,
            sampleCount: samples.count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample!
    }
}
