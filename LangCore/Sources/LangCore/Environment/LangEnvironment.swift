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

    private static let log = Logger(subsystem: "com.surreptus.Kikimi", category: "dictionary")

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

    static let folderName = "Kikimi"
    static let databaseName = "kikimi.sqlite"

    /// The app's own folder inside its sandbox container.
    public static func standard() throws -> LangEnvironment {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try LangEnvironment(root: support.appending(path: folderName, directoryHint: .isDirectory))
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
