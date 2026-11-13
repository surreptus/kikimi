import AVFoundation
import Foundation

public enum AudioExtractionError: Error, DetailedError {
    case noAudioTrack
    case readerFailed(Error?)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: String(localized: "This file has no audio track. Try a video with sound, or add a subtitles file.", bundle: .module)
        case .readerFailed: String(localized: "Kikimi couldn't read this video's sound. The file may be damaged. Try a different copy.", bundle: .module)
        }
    }

    public var detail: String {
        switch self {
        case .noAudioTrack: "noAudioTrack"
        case .readerFailed(let e): "readerFailed: \(e.map(Problem.rawDetail(of:)) ?? "unknown error")"
        }
    }
}

public enum AudioExtractor {
    public static let sampleRate = 16_000.0

    /// Decodes the first audio track to 16 kHz mono Float32 PCM with AVAssetReader.
    /// `limit` stops after that many seconds (used for language detection, which only needs the opening).
    public static func pcm16kMono(from url: URL, limit: Double? = nil) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioExtractionError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        if let limit { reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: limit, preferredTimescale: 600)) }
        guard reader.startReading() else { throw AudioExtractionError.readerFailed(reader.error) }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                    destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
        }
        if reader.status == .failed { throw AudioExtractionError.readerFailed(reader.error) }
        return samples
    }
}
