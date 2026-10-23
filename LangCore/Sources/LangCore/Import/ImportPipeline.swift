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

    public func importVideo(
        from original: URL, profile: any LanguageProfile, model: String? = nil, checkLanguage: Bool = true,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> Video {
        let scoped = original.startAccessingSecurityScopedResource()
        defer { if scoped { original.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default

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
            // 1. Stage a copy. The original is read, never modified.
            progress(ImportProgress(stage: .staging, fraction: 0))
            let staged = work.appending(path: "source." + original.pathExtension)
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                try fm.copyItem(at: original, to: staged)
                let sizes = try [original, staged].map { try fm.attributesOfItem(atPath: $0.path)[.size] as? UInt64 }
                guard sizes[0] == sizes[1] else { throw CocoaError(.fileReadCorruptFile) }
            } catch { throw Self.wrapped(error, ImportError.copyFailed) }

            try Task.checkCancellation()

            // Importing a Japanese video as Spanish would produce nonsense words, so check the spoken language first.
            // Detection is only advice: if it fails or is unsure, the import carries on as chosen.
            if checkLanguage {
                progress(ImportProgress(stage: .detectingLanguage, fraction: 0))
                if let guess = try? await transcriber.detectLanguage(mediaURL: staged, model: model ?? profile.defaultModel),
                   guess.confidence >= Self.languageConfidence, guess.code != profile.whisperCode,
                   let other = LanguageProfiles.all.first(where: { $0.whisperCode == guess.code }) {
                    throw ImportError.languageMismatch(detected: other.code, chosen: profile.code, confidence: guess.confidence)
                }
            }

            try Task.checkCancellation()

            // 2. Transcribe. Failing here has changed nothing.
            let segments: [TranscriptSegment]
            progress(ImportProgress(stage: .transcribing, fraction: 0))
            do {
                segments = try await transcriber.transcribe(
                    mediaURL: staged, whisperCode: profile.whisperCode, model: model ?? profile.defaultModel,
                    progress: { progress(ImportProgress(stage: .transcribing, fraction: $0)) })
            } catch { throw Self.wrapped(error, ImportError.transcriptionFailed) }

            try Task.checkCancellation()

            // 3. Re-encode to a temp file.
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

            // 4. Verify the output against the staged source.
            progress(ImportProgress(stage: .verifying, fraction: 0))
            let duration: Double
            do { duration = try await MediaVerifier.duration(of: staged) }
            catch { throw ImportError.verificationFailed("source unreadable: \(error)") }
            try await MediaVerifier.verify(output: videoOut, expectedDuration: duration)

            try Task.checkCancellation()

            // 5. Compact audio track.
            progress(ImportProgress(stage: .extractingAudio, fraction: 0))
            do { try await transcoder.extractAAC(source: staged, destination: audioOut) }
            catch { throw Self.wrapped(error, ImportError.audioExportFailed) }

            // The last point where a cancel is honoured: after this the video is moved in and saved as one unit.
            try Task.checkCancellation()

            // 6. Atomic move into the library (one directory rename), then one DB transaction.
            progress(ImportProgress(stage: .saving, fraction: 0))
            let destination = libraryRoot.appending(path: hash, directoryHint: .isDirectory)
            do {
                try fm.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
                try fm.moveItem(at: out, to: destination)
            } catch { throw ImportError.libraryMoveFailed(error) }
            libraryDir = destination

            let analysed = segments.map { (segment: $0, tokens: profile.contentWords(in: $0.text)) }
            let video = Video(
                language: profile.code, title: original.deletingPathExtension().lastPathComponent,
                contentHash: hash, videoPath: "\(hash)/video.mov", audioPath: "\(hash)/audio.m4a",
                duration: duration)
            let saved: Video
            do { saved = try await database.saveImport(video: video, subtitles: analysed) }
            catch { throw Self.wrapped(error, ImportError.databaseFailed) }

            // 7. Only now drop the staged copy. Failure to delete it must not fail a committed import.
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
}
