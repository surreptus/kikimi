import Foundation
import GRDB

public struct VideoDetails: Sendable {
    public let video: Video
    public let subtitleCount: Int
    /// Distinct words found in this video.
    public let wordCount: Int
    /// The video's own folder in the library (video and audio live here).
    public let folder: URL
    public let videoBytes: Int64
    public let audioBytes: Int64
    /// True if the files have gone missing from disk.
    public let filesMissing: Bool
    public var totalBytes: Int64 { videoBytes + audioBytes }
}

public struct VideoDeletion: Sendable {
    public let freedBytes: Int64
    /// Words that were still "new" and appeared in no other video.
    public let removedWords: Int
}

public enum VideoStorageError: Error, LocalizedError {
    case unsafePath(String)
    case filesRemain(URL)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path): "Refusing to delete \(path): it isn't inside the library."
        case .filesRemain(let url): "The video was removed from the app but its files couldn't be deleted: \(url.path)"
        }
    }
}

extension LangDatabase {
    /// Deletes the video with its subtitles and occurrences. Words you've worked on are kept; untouched ("new")
    /// words that no longer appear in any video are removed. Returns how many of those were removed.
    func deleteVideoRows(id: Int64) async throws -> Int {
        try await writer.write { db in
            guard let video = try Video.fetchOne(db, key: id) else { throw LangError.notFound }
            _ = try video.delete(db)   // subtitles and occurrences cascade
            try db.execute(sql: """
                DELETE FROM words
                WHERE language = ? AND status = 'new'
                  AND NOT EXISTS (SELECT 1 FROM occurrences WHERE occurrences.word_id = words.id)
                """, arguments: [video.language])
            return db.changesCount
        }
    }

    func wordCount(videoID: Int64) async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT occurrences.word_id) FROM occurrences
                JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                WHERE subtitles.video_id = ?
                """, arguments: [videoID]) ?? 0
        }
    }
}

extension LangEnvironment {
    /// The video's folder inside the library, or nil if its stored path doesn't resolve to one (never delete outside it).
    func libraryFolder(for video: Video) -> URL? {
        let parts = video.videoPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let first = parts.first, !first.isEmpty, first != ".", first != ".." else { return nil }
        let library = libraryURL.standardizedFileURL
        let folder = library.appending(path: first, directoryHint: .isDirectory).standardizedFileURL
        return folder.deletingLastPathComponent() == library ? folder : nil
    }

    private func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return walker.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(0) { $0 + Int64($1) }
    }

    public func details(for video: Video) async throws -> VideoDetails {
        let videoURL = fileURL(for: video)
        let audioURL = video.audioPath.map { libraryURL.appending(path: $0) }
        let counts = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM subtitles WHERE video_id = ?", arguments: [video.id!]) ?? 0
        }
        return VideoDetails(
            video: video, subtitleCount: counts,
            wordCount: try await database.wordCount(videoID: video.id!),
            folder: libraryFolder(for: video) ?? videoURL.deletingLastPathComponent(),
            videoBytes: fileSize(videoURL), audioBytes: audioURL.map(fileSize) ?? 0,
            filesMissing: !FileManager.default.fileExists(atPath: videoURL.path))
    }

    /// Disk used by one video (video + audio).
    public func bytesOnDisk(for video: Video) -> Int64 {
        fileSize(fileURL(for: video)) + (video.audioPath.map { fileSize(libraryURL.appending(path: $0)) } ?? 0)
    }

    /// Disk used by the whole library folder.
    public func libraryBytes() -> Int64 { folderSize(libraryURL) }

    /// Removes the app's copy of a video. Your original file (wherever you imported it from) is never touched.
    @discardableResult
    public func deleteVideo(_ video: Video) async throws -> VideoDeletion {
        guard let id = video.id else { throw LangError.notFound }
        guard let folder = libraryFolder(for: video) else { throw VideoStorageError.unsafePath(video.videoPath) }

        let freed = folderSize(folder)
        let removedWords = try await database.deleteVideoRows(id: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) }
            catch { throw VideoStorageError.filesRemain(folder) }
        }
        return VideoDeletion(freedBytes: freed, removedWords: removedWords)
    }
}
