import Foundation

/// Imports a dropped video. The original is only ever read; the pipeline deletes nothing outside its own
/// `Staging/` and `Library/` directories under `root`.
public actor ImportPipeline {
    private let database: LangDatabase
    private let stagingRoot: URL
    private let libraryRoot: URL
    private let transcriber: any Transcriber
    private let transcoder: any MediaTranscoder
    private var inFlight = Set<String>()
    /// How sure Whisper must be before the import is stopped for a language check.
    static let languageConfidence = 0.6

    /// A cancel that lands inside a step stays a cancellation instead of being reported as that step failing.
    private static func wrapped(_ error: Error, _ make: (Error) -> ImportError) -> Error {
        error is CancellationError || Task.isCancelled ? CancellationError() : make(error)
    }

    public init(
        database: LangDatabase, root: URL, transcriber: any Transcriber,
        transcoder: any MediaTranscoder = AVFoundationTranscoder()
    ) {
        self.database = database
        self.stagingRoot = root.appending(path: "Staging", directoryHint: .isDirectory)
        self.libraryRoot = root.appending(path: "Library", directoryHint: .isDirectory)
        self.transcriber = transcriber
        self.transcoder = transcoder
    }

    /// Call once at launch: removes staging copies left behind by a crash.
    public func cleanOrphanedStaging() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
    }

    /// Runs the steps in order; each is a method below. A cancel is honoured between steps, up to the point where
    /// the video is moved into the library, after which the move and the database write finish as one unit.
    public func importVideo(
        from original: URL, profile: any LanguageProfile, model: String? = nil, checkLanguage: Bool = true,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> Video {
        let scoped = original.startAccessingSecurityScopedResource()
        defer { if scoped { original.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let model = model ?? profile.defaultModel

        progress(ImportProgress(stage: .hashing, fraction: 0))
        let hash = try await FileHasher.sha256(of: original)
        if let existing = try await database.videoID(forContentHash: hash) {
            throw ImportError.duplicate(existingVideoID: existing)
        }
        guard inFlight.insert(hash).inserted else { throw ImportError.duplicate(existingVideoID: nil) }
        defer { inFlight.remove(hash) }

        let work = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var libraryDir: URL?
        do {
            let staged = try stage(original, in: work, progress: progress)
            try Task.checkCancellation()

            if checkLanguage { try await confirmLanguage(of: staged, profile: profile, model: model, progress: progress) }
            try Task.checkCancellation()

            let segments = try await transcribe(staged, profile: profile, model: model, progress: progress)
            try Task.checkCancellation()

            let files = try await makeLibraryFiles(from: staged, in: work, progress: progress)
            // The last point where a cancel is honoured.
            try Task.checkCancellation()

            progress(ImportProgress(stage: .saving, fraction: 0))
            let destination = libraryRoot.appending(path: hash, directoryHint: .isDirectory)
            try moveIntoLibrary(files, to: destination)
            libraryDir = destination   // set only after the move, so a failed move never deletes an existing folder
            let video = Video(
                language: profile.code, title: original.deletingPathExtension().lastPathComponent,
                contentHash: hash, videoPath: "\(hash)/video.mov", audioPath: "\(hash)/audio.m4a",
                duration: files.duration)
            let saved = try await save(video, segments: segments, profile: profile)

            // Only now drop the staged copy. Failure to delete it must not fail a committed import.
            try? fm.removeItem(at: work)
            progress(ImportProgress(stage: .saving, fraction: 1))
            return saved
        } catch {
            // Remove only what this import created.
            try? fm.removeItem(at: work)
            if let libraryDir { try? fm.removeItem(at: libraryDir) }
            throw error
        }
    }

    // MARK: Steps

    /// 1. Copy the original into staging and check the copy's size. The original is read, never modified.
    private func stage(_ original: URL, in work: URL, progress: ProgressHandler) throws -> URL {
        progress(ImportProgress(stage: .staging, fraction: 0))
        let fm = FileManager.default
        let staged = work.appending(path: "source." + original.pathExtension)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.copyItem(at: original, to: staged)
            let sizes = try [original, staged].map { try fm.attributesOfItem(atPath: $0.path)[.size] as? UInt64 }
            guard sizes[0] == sizes[1] else { throw CocoaError(.fileReadCorruptFile) }
        } catch { throw Self.wrapped(error, ImportError.copyFailed) }
        return staged
    }

    /// Importing a Japanese video as Spanish would produce nonsense words, so check the spoken language first.
    /// Detection is only advice: if it fails or is unsure, the import carries on as chosen.
    private func confirmLanguage(
        of staged: URL, profile: any LanguageProfile, model: String, progress: ProgressHandler
    ) async throws {
        progress(ImportProgress(stage: .detectingLanguage, fraction: 0))
        // Usually the first thing to need the model, so a slow load shows up here; a failure is left for the transcribe
        // step to report, since this check is only advice.
        try? await prepareModel(model, stage: .detectingLanguage, progress: progress, failing: false)
        if let guess = try? await transcriber.detectLanguage(mediaURL: staged, model: model),
           guess.confidence >= Self.languageConfidence, guess.code != profile.whisperCode,
           let other = LanguageProfiles.all.first(where: { $0.whisperCode == guess.code }) {
            throw ImportError.languageMismatch(detected: other.code, chosen: profile.code, confidence: guess.confidence)
        }
    }

    /// 2. Transcribe. Failing here has changed nothing.
    private func transcribe(
        _ staged: URL, profile: any LanguageProfile, model: String, progress: @escaping ProgressHandler
    ) async throws -> [TranscriptSegment] {
        progress(ImportProgress(stage: .transcribing, fraction: 0))
        // Already loaded if the language check ran; otherwise this is where a slow load happens.
        try await prepareModel(model, stage: .transcribing, progress: progress, failing: true)
        do {
            return try await transcriber.transcribe(
                mediaURL: staged, whisperCode: profile.whisperCode, model: model,
                progress: { progress(ImportProgress(stage: .transcribing, fraction: $0)) })
        } catch { throw Self.wrapped(error, ImportError.transcriptionFailed) }
    }

    /// Loads the model if it isn't already, saying so while it does: the first load can take minutes, and the bar
    /// has nothing to show for it. Nothing is reported when it is already loaded.
    private func prepareModel(
        _ model: String, stage: ImportStage, progress: ProgressHandler, failing: Bool
    ) async throws {
        guard await !transcriber.isModelLoaded(model) else { return }
        progress(ImportProgress(stage: stage, fraction: 0, note: .loadingModel))
        do { try await transcriber.loadModel(model) }
        catch { if failing { throw Self.wrapped(error, ImportError.transcriptionFailed) } }
        progress(ImportProgress(stage: stage, fraction: 0))   // clears the note
    }

    /// The library files built in staging, before they are moved in.
    private struct LibraryFiles {
        var folder: URL
        var duration: Double
    }

    /// 3-5. Make the compact video, verify it against the staged source, then export the AAC audio.
    private func makeLibraryFiles(
        from staged: URL, in work: URL, progress: @escaping ProgressHandler
    ) async throws -> LibraryFiles {
        let fm = FileManager.default
        let out = work.appending(path: "out", directoryHint: .isDirectory)
        let videoOut = out.appending(path: "video.mov")
        let audioOut = out.appending(path: "audio.m4a")
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try await transcoder.compactVideo(
                source: staged, destination: videoOut,
                progress: { progress(ImportProgress(stage: .transcoding, fraction: $0)) })
        } catch { throw Self.wrapped(error, ImportError.transcodeFailed) }
        try Task.checkCancellation()

        progress(ImportProgress(stage: .verifying, fraction: 0))
        let duration: Double
        do { duration = try await MediaVerifier.duration(of: staged) }
        catch { throw ImportError.verificationFailed("source unreadable: \(error)") }
        try await MediaVerifier.verify(output: videoOut, expectedDuration: duration)
        try Task.checkCancellation()

        progress(ImportProgress(stage: .extractingAudio, fraction: 0))
        do { try await transcoder.extractAAC(source: staged, destination: audioOut) }
        catch { throw Self.wrapped(error, ImportError.audioExportFailed) }
        return LibraryFiles(folder: out, duration: duration)
    }

    /// 6. Move the files into the library with one directory rename.
    private func moveIntoLibrary(_ files: LibraryFiles, to destination: URL) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
            try fm.moveItem(at: files.folder, to: destination)
        } catch { throw ImportError.libraryMoveFailed(error) }
    }

    /// Write every row in one transaction. If this fails the caller removes the moved folder.
    private func save(
        _ video: Video, segments: [TranscriptSegment], profile: any LanguageProfile
    ) async throws -> Video {
        let analysed = segments.map { (segment: $0, tokens: profile.contentWords(in: $0.text)) }
        do { return try await database.saveImport(video: video, subtitles: analysed) }
        catch { throw Self.wrapped(error, ImportError.databaseFailed) }
    }
}
