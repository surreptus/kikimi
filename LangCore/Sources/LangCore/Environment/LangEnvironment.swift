import Foundation
import os

/// Everything the UI needs, wired together. The app target creates one of these and calls into it.
public final class LangEnvironment: Sendable {
    public let root: URL
    public let database: LangDatabase
    public let models: ModelManager
    public let preferences: ModelPreferences
    public let reviewAudio: ReviewAudioPreferences
    public let pipeline: ImportPipeline

    private static let log = Logger(subsystem: "com.surreptus.Reprise", category: "dictionary")

    /// `dictionaries` defaults to the ones bundled in the app; tests pass small fixture files.
    public init(
        root: URL, defaults: UserDefaults = .standard, transcriber: (any Transcriber)? = nil,
        dictionaries: DictionaryStore? = nil
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let store = try dictionaries ?? DictionaryStore.bundled(for: LanguageProfiles.all)
        database = try LangDatabase(path: root.appending(path: Self.databaseName).path, dictionaries: store)
        models = ModelManager(directory: root.appending(path: "Models", directoryHint: .isDirectory))
        preferences = ModelPreferences(defaults: defaults)
        reviewAudio = ReviewAudioPreferences(defaults: defaults)
        pipeline = ImportPipeline(
            database: database, root: root, transcriber: transcriber ?? WhisperKitTranscriber(models: models))
    }

    static let folderName = "Reprise"
    static let databaseName = "reprise.sqlite"
    /// The app was first called LangSRS, and its folder and database carried that name.
    static let legacyFolderName = "LangSRS"
    static let legacyDatabaseName = "langsrs.sqlite"

    /// The app's own folder inside its sandbox container.
    public static func standard() throws -> LangEnvironment {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try migrateLegacyLayout(in: support)
        return try LangEnvironment(root: support.appending(path: folderName, directoryHint: .isDirectory))
    }

    /// Moves data kept under the old name to the current one, before the database opens. It only ever moves:
    /// nothing is copied over or deleted. If the current folder already holds a database it is left alone, and
    /// if it holds none (a first launch that found nothing) it is set aside, not removed, to make way.
    static func migrateLegacyLayout(in support: URL) throws {
        let fm = FileManager.default
        let legacy = support.appending(path: legacyFolderName, directoryHint: .isDirectory)
        let current = support.appending(path: folderName, directoryHint: .isDirectory)
        guard fm.fileExists(atPath: legacy.path) else { return }

        if fm.fileExists(atPath: current.path) {
            if fm.fileExists(atPath: current.appending(path: databaseName).path) {
                log.notice("both the old and new data folders exist; using the new one and leaving the old alone")
                return
            }
            let aside = support.appending(path: "\(folderName).before-migration", directoryHint: .isDirectory)
            try fm.moveItem(at: current, to: uniqueURL(for: aside))
        }
        try fm.moveItem(at: legacy, to: current)
        for suffix in ["", "-wal", "-shm"] {
            let old = current.appending(path: legacyDatabaseName + suffix)
            let new = current.appending(path: databaseName + suffix)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try fm.moveItem(at: old, to: new) }
        }
        log.notice("moved the data folder from \(legacyFolderName, privacy: .public) to \(folderName, privacy: .public)")
    }

    /// `url`, or `url` with a number added if something is already there.
    private static func uniqueURL(for url: URL) -> URL {
        var candidate = url, n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appending(path: url.lastPathComponent + "-\(n)", directoryHint: .isDirectory)
            n += 1
        }
        return candidate
    }

    /// Launch-time work: drop crash leftovers, and prove every dictionary opens and has entries, so a broken
    /// install fails here with a clear message instead of as empty lookups later.
    public func prepare() async throws {
        await pipeline.cleanOrphanedStaging()
        for language in database.dictionaries.languages {
            let count = try await database.dictionaries.entryCount(language: language)
            guard count > 0 else { throw DictionaryError.missingResource("dictionary-\(language) is empty") }
            Self.log.notice("dictionary \(language, privacy: .public): \(count) entries, read in place from the app bundle")
        }
    }

    public var libraryURL: URL { root.appending(path: "Library", directoryHint: .isDirectory) }

    public func fileURL(for video: Video) -> URL {
        root.appending(path: "Library", directoryHint: .isDirectory).appending(path: video.videoPath)
    }
}
