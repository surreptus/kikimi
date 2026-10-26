import Foundation
import GRDB

/// The videos in a full backup: what each is, and its transcript. The compressed video files sit beside this file in
/// `Library/<hash>/`. Words are not stored here: they are found again from the transcript, as when a video is added.
public struct LibraryBackup: Codable, Equatable, Sendable {
    public static let format = "kikimi-library"
    public static let currentVersion = 1

    public var format = LibraryBackup.format
    public var version = LibraryBackup.currentVersion
    public var videos: [Entry]

    public struct Entry: Codable, Equatable, Sendable {
        public var language: String
        public var title: String
        public var contentHash: String
        public var videoPath: String
        public var audioPath: String?
        public var duration: Double
        public var importedAt: Date
        public var resumePosition: Double?
        public var lines: [Line]
    }

    public struct Line: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
    }

    /// A path from a file is only trusted if it names a file directly inside the video's own folder: `<hash>/<name>`.
    static func isSafe(_ path: String, hash: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 && parts[0] == hash && !parts[1].isEmpty && parts[1] != "." && parts[1] != ".."
    }

    static func isSafeHash(_ hash: String) -> Bool {
        !hash.isEmpty && hash.count <= 128 && hash.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

/// What restoring a backup folder would do, for the preview.
public struct FullBackupPreview: Equatable, Sendable {
    public var progress: BackupPreview
    public var videosToAdd = 0
    public var videosAlreadyHere = 0
    /// Videos the folder lists but whose files are missing from it.
    public var videosMissingFiles = 0
    public var bytesToCopy: Int64 = 0
}

public struct FullBackupSummary: Equatable, Sendable {
    public var folder: URL
    public var videos: Int
    public var words: Int
    public var bytes: Int64
}

extension LangEnvironment {
    public static let progressFileName = "progress.\(ProgressBackup.fileExtension)"
    public static let libraryFileName = "library.json"

    /// Whether `url` is a folder holding a full backup.
    public static func isFullBackup(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        return FileManager.default.fileExists(atPath: url.appending(path: progressFileName).path)
    }

    // MARK: Save

    /// Writes a full backup into a new folder inside `parent`: your progress, every video's transcript, and the compressed
    /// video copies. Your original files are not touched, and nothing existing is overwritten.
    public func writeFullBackup(
        in parent: URL, name: String, extraSettings: [String: String] = [:]
    ) async throws -> FullBackupSummary {
        let fm = FileManager.default
        var folder = parent.appending(path: name, directoryHint: .isDirectory)
        var n = 2
        while fm.fileExists(atPath: folder.path) { folder = parent.appending(path: "\(name) \(n)", directoryHint: .isDirectory); n += 1 }
        try fm.createDirectory(at: folder.appending(path: "Library", directoryHint: .isDirectory), withIntermediateDirectories: true)

        let progress = try await makeBackup(extraSettings: extraSettings)
        try progress.write(to: folder.appending(path: Self.progressFileName), options: .atomic)

        let videos = try await database.writer.read { db in try Video.order(Column("id")).fetchAll(db) }
        var entries: [LibraryBackup.Entry] = []
        var bytes: Int64 = 0
        for video in videos {
            let lines = try await database.subtitles(videoID: video.id!)
            entries.append(.init(
                language: video.language, title: video.title, contentHash: video.contentHash, videoPath: video.videoPath,
                audioPath: video.audioPath, duration: video.duration, importedAt: video.importedAt,
                resumePosition: video.resumePosition,
                lines: lines.map { .init(start: $0.startTime, end: $0.endTime, text: $0.text) }))
            if let source = libraryFolder(for: video), fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: folder.appending(path: "Library/\(source.lastPathComponent)", directoryHint: .isDirectory))
                bytes += bytesOnDisk(for: video)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(LibraryBackup(videos: entries)).write(to: folder.appending(path: Self.libraryFileName), options: .atomic)
        let words = try ProgressBackup.decode(progress).words.count
        return FullBackupSummary(folder: folder, videos: entries.count, words: words, bytes: bytes)
    }

    // MARK: Restore

    private func readLibrary(at folder: URL) throws -> LibraryBackup {
        let url = folder.appending(path: Self.libraryFileName)
        guard let data = try? Data(contentsOf: url) else { return LibraryBackup(videos: []) }   // a progress-only folder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let library = try? decoder.decode(LibraryBackup.self, from: data), library.format == LibraryBackup.format else {
            throw BackupError.damaged
        }
        guard library.version <= LibraryBackup.currentVersion else { throw BackupError.newerVersion(library.version) }
        return library
    }

    private func isUsable(_ entry: LibraryBackup.Entry, in folder: URL) -> Bool {
        guard LibraryBackup.isSafeHash(entry.contentHash), LibraryBackup.isSafe(entry.videoPath, hash: entry.contentHash),
              entry.audioPath.map({ LibraryBackup.isSafe($0, hash: entry.contentHash) }) ?? true,
              LanguageProfiles.profile(for: entry.language) != nil else { return false }
        return FileManager.default.fileExists(atPath: folder.appending(path: "Library/\(entry.videoPath)").path)
    }

    public func previewFullBackup(at folder: URL, appSettingKeys: Set<String> = []) async throws -> FullBackupPreview {
        let progress = try await previewBackup(Data(contentsOf: folder.appending(path: Self.progressFileName)), appSettingKeys: appSettingKeys)
        var preview = FullBackupPreview(progress: progress)
        for entry in try readLibrary(at: folder).videos {
            if try await database.videoID(forContentHash: entry.contentHash) != nil { preview.videosAlreadyHere += 1 }
            else if isUsable(entry, in: folder) {
                preview.videosToAdd += 1
                let dir = folder.appending(path: "Library/\(entry.contentHash)", directoryHint: .isDirectory)
                let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                preview.bytesToCopy += files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            } else { preview.videosMissingFiles += 1 }
        }
        return preview
    }

    /// Adds the videos that aren't here yet (with their transcripts and words), then restores progress as for a
    /// progress-only backup. Safe to run twice: videos already here are skipped, and progress is never overwritten.
    public func restoreFullBackup(
        from folder: URL, includingSettings: Bool, appSettingKeys: Set<String> = []
    ) async throws -> (report: ProgressImportReport, videosAdded: Int, appSettings: [String: String]) {
        let fm = FileManager.default
        var added = 0
        for entry in try readLibrary(at: folder).videos {
            guard isUsable(entry, in: folder), try await database.videoID(forContentHash: entry.contentHash) == nil,
                  let profile = LanguageProfiles.profile(for: entry.language) else { continue }
            let destination = libraryURL.appending(path: entry.contentHash, directoryHint: .isDirectory)
            guard !fm.fileExists(atPath: destination.path) else { continue }   // files without a row: leave them alone
            let staging = libraryURL.appending(path: ".restoring-\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                try fm.createDirectory(at: libraryURL, withIntermediateDirectories: true)
                try fm.copyItem(at: folder.appending(path: "Library/\(entry.contentHash)", directoryHint: .isDirectory), to: staging)
                try fm.moveItem(at: staging, to: destination)
                let analysed = entry.lines.map { line in
                    (segment: TranscriptSegment(start: line.start, end: line.end, text: line.text),
                     tokens: profile.contentWords(in: line.text))
                }
                try await database.saveImport(
                    video: Video(language: entry.language, title: entry.title, contentHash: entry.contentHash,
                                 videoPath: entry.videoPath, audioPath: entry.audioPath, duration: entry.duration,
                                 importedAt: entry.importedAt, resumePosition: entry.resumePosition),
                    subtitles: analysed)
                added += 1
            } catch {
                try? fm.removeItem(at: staging)
                try? fm.removeItem(at: destination)   // only what this restore made
                throw error
            }
        }
        let progress = try Data(contentsOf: folder.appending(path: Self.progressFileName))
        let result = try await restoreBackup(progress, includingSettings: includingSettings, appSettingKeys: appSettingKeys)
        return (result.report, added, result.appSettings)
    }
}
