import AVFoundation
import Foundation

public enum ClipKind: Sendable {
    case audio   // AAC in .m4a, cut from the library's audio track
    case video   // H.264 + AAC in .mp4, cut from the library video

    public var fileExtension: String { self == .audio ? "m4a" : "mp4" }
}

public enum ClipError: Error {
    case missingSource(URL)
    case emptyRange
    case presetUnavailable
}

/// Cuts sentence clips out of imported videos. Reads the library; writes only to the destination it is given.
public struct ClipExporter: Sendable {
    public static let defaultPadding = 0.15

    public let libraryRoot: URL

    public init(libraryRoot: URL) { self.libraryRoot = libraryRoot }

    /// Exports `start...end` (seconds) plus `padding` on each side, clamped to the media's length.
    public func export(
        video: Video, start: Double, end: Double, kind: ClipKind,
        padding: Double = ClipExporter.defaultPadding, to destination: URL
    ) async throws {
        let path = kind == .audio ? (video.audioPath ?? video.videoPath) : video.videoPath
        let source = libraryRoot.appending(path: path)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ClipError.missingSource(source) }

        let asset = AVURLAsset(url: source)
        let total = try await asset.load(.duration).seconds
        let from = max(0, start - padding), to = min(total, end + padding)
        guard to > from else { throw ClipError.emptyRange }

        let preset = kind == .audio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ClipError.presetUnavailable
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 600),
            end: CMTime(seconds: to, preferredTimescale: 600))
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: kind == .audio ? .m4a : .mp4)
    }

    /// A filesystem-safe name fragment.
    public static func sanitized(_ name: String, limit: Int = 60) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        let trimmed = String(cleaned.prefix(limit))
        return trimmed.isEmpty ? "clip" : trimmed
    }

    /// `base.ext`, or `base 2.ext`, `base 3.ext`… if that name is taken.
    public static func uniqueURL(in directory: URL, base: String, ext: String) -> URL {
        var candidate = directory.appending(path: "\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

extension LangEnvironment {
    public var clips: ClipExporter {
        ClipExporter(libraryRoot: root.appending(path: "Library", directoryHint: .isDirectory))
    }

    public func audioURL(for video: Video) -> URL {
        root.appending(path: "Library", directoryHint: .isDirectory).appending(path: video.audioPath ?? video.videoPath)
    }

    public func playback(for video: Video) async throws -> PlaybackController {
        let lines = try await database.subtitles(videoID: video.id!)
        return await PlaybackController(url: fileURL(for: video), lines: lines)
    }

    /// Exports one clip per example line of a word into `directory`. Returns the files written.
    @discardableResult
    public func exportClips(
        forWord wordID: Int64, kind: ClipKind, into directory: URL, limit: Int = 20
    ) async throws -> [URL] {
        let word = try await database.writer.read { try Word.fetchOne($0, key: wordID) }
        guard let word else { throw LangError.notFound }
        let lines = try await database.examples(wordID: wordID, limit: limit)
        var written: [URL] = []
        for (index, line) in lines.enumerated() {
            guard let video = try await database.video(id: line.videoID) else { continue }
            let base = "\(ClipExporter.sanitized(word.lemma))-\(index + 1)"
            let destination = ClipExporter.uniqueURL(in: directory, base: base, ext: kind.fileExtension)
            try await clips.export(video: video, start: line.startTime, end: line.endTime, kind: kind, to: destination)
            written.append(destination)
        }
        return written
    }
}
