import Foundation

/// Everything the UI needs, wired together. The app target creates one of these and calls into it.
public final class LangEnvironment: Sendable {
    public let root: URL
    public let database: LangDatabase
    public let models: ModelManager
    public let preferences: ModelPreferences
    public let reviewAudio: ReviewAudioPreferences
    public let pipeline: ImportPipeline

    public init(root: URL, defaults: UserDefaults = .standard, transcriber: (any Transcriber)? = nil) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        database = try LangDatabase(path: root.appending(path: "langsrs.sqlite").path)
        models = ModelManager(directory: root.appending(path: "Models", directoryHint: .isDirectory))
        preferences = ModelPreferences(defaults: defaults)
        reviewAudio = ReviewAudioPreferences(defaults: defaults)
        pipeline = ImportPipeline(
            database: database, root: root, transcriber: transcriber ?? WhisperKitTranscriber(models: models))
    }

    /// The app's own folder inside its sandbox container.
    public static func standard() throws -> LangEnvironment {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try LangEnvironment(root: support.appending(path: "LangSRS", directoryHint: .isDirectory))
    }

    /// Launch-time work: drop crash leftovers and load bundled dictionaries on first run.
    public func prepare() async throws {
        await pipeline.cleanOrphanedStaging()
        for profile in LanguageProfiles.all {
            try await database.importBundledDictionary(for: profile)
        }
    }

    public var libraryURL: URL { root.appending(path: "Library", directoryHint: .isDirectory) }

    public func fileURL(for video: Video) -> URL {
        root.appending(path: "Library", directoryHint: .isDirectory).appending(path: video.videoPath)
    }
}
