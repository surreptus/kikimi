import AVFoundation
import Foundation

/// Why a file can't be added as a video. Found when the file is added, so it is refused with a reason at once, not after Start.
public enum MediaProblem: Sendable, Equatable {
    /// macOS can't open it: a format it doesn't read (WebM and MKV, among others), or a damaged file.
    case cannotOpen
    /// It opens, but has no picture: an audio file.
    case noVideo

    /// The formats macOS can't open, by extension, so the message can name the likely cause.
    static let unreadableFormats: Set<String> = ["webm", "mkv"]

    public func message(for url: URL) -> String {
        let name = url.lastPathComponent
        switch self {
        case .cannotOpen where Self.unreadableFormats.contains(url.pathExtension.lowercased()):
            return String(localized: "“\(name)” can't be opened: macOS can't read WebM or MKV files. Convert it to MP4 first.", bundle: .module)
        case .cannotOpen:
            return String(localized: "“\(name)” can't be opened. It may be damaged, or in a format macOS can't read.", bundle: .module)
        case .noVideo:
            return String(localized: "“\(name)” has no video. Kikimi adds video files; audio-only files aren't supported yet.", bundle: .module)
        }
    }

    /// For a file that is neither a video nor a subtitle file.
    public static func notAVideo(_ url: URL) -> String {
        String(localized: "“\(url.lastPathComponent)” isn't a video. Kikimi adds video files, with .srt or .vtt subtitles.", bundle: .module)
    }
}

public enum MediaCheck {
    /// nil when macOS opens the file and it has a video track, and also nil when this process cannot read the file at all: a
    /// sandboxed app may read a chosen file only while it holds the file's security scope, and the import asks for that itself.
    /// Without the scope a good file looks damaged, so a file that cannot be read here is left for the import to judge.
    public static func problem(with url: URL) async -> MediaProblem? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isReadable) else { return .cannotOpen }
            return try await asset.loadTracks(withMediaType: .video).isEmpty ? .noVideo : nil
        } catch {
            return .cannotOpen
        }
    }
}
