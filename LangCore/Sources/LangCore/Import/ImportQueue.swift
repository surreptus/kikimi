import Foundation
import Observation

extension ImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicate: String(localized: "Already imported.", bundle: .module)
        case .languageMismatch(let detected, let chosen, _):
            String(localized: "This sounds like \(LanguageProfiles.profile(for: detected)?.displayName ?? detected), not \(LanguageProfiles.profile(for: chosen)?.displayName ?? chosen).", bundle: .module)
        case .copyFailed(let e): String(localized: "Couldn't copy the file: \(e.localizedDescription)", bundle: .module)
        case .transcriptionFailed(let e): Self.describe(transcription: e)
        case .transcodeFailed(let e): String(localized: "Couldn't re-encode the video: \(e.localizedDescription)", bundle: .module)
        case .verificationFailed(let why): String(localized: "The re-encoded video failed verification (\(why)). Your original is untouched.", bundle: .module)
        case .libraryMoveFailed(let e): String(localized: "Couldn't save to the library: \(e.localizedDescription)", bundle: .module)
        case .databaseFailed(let e): String(localized: "Couldn't save to the database: \(e.localizedDescription)", bundle: .module)
        }
    }

    private static func describe(transcription error: Error) -> String {
        switch error {
        case ModelError.notInstalled: String(localized: "The speech model isn't downloaded yet.", bundle: .module)
        case AudioExtractionError.noAudioTrack: String(localized: "This file has no audio track.", bundle: .module)
        default: String(localized: "Transcription failed: \(error.localizedDescription)", bundle: .module)
        }
    }
}

/// Runs dropped files through the import pipeline one at a time and publishes per-file status.
@MainActor @Observable
public final class ImportQueue {
    public enum Status: Equatable, Sendable {
        case queued
        case running(ImportStage, Double)
        case imported
        case duplicate
        /// Stopped before transcribing: the audio sounds like another supported language (that profile's code).
        case languageMismatch(detected: String)
        /// Cancel was pressed on a running import; it stops at the next safe point.
        case cancelling
        case cancelled
        case failed(String)
    }

    public struct Job: Identifiable, Sendable {
        public let id = UUID()
        public let url: URL
        public fileprivate(set) var status: Status = .queued
        public fileprivate(set) var profile: any LanguageProfile
        fileprivate(set) var model: String
        public let quality: VideoQuality
        fileprivate var skipsLanguageCheck = false
        public var fileName: String { url.lastPathComponent }
        /// False for an import the user chose to go ahead with after a language warning.
        public var checksLanguage: Bool { !skipsLanguageCheck }
        /// False when the video is kept as it is, so there is no compressing step to count.
        public var compresses: Bool { quality == .smallest }
        /// What is worth saying about the current step, such as that the model is loading.
        public fileprivate(set) var note: ImportNote?
        /// When the current step began (or, if the model was loading, when that finished), for the time left.
        public fileprivate(set) var stageStartedAt: Date?
    }

    public private(set) var jobs: [Job] = []
    public var isBusy: Bool { jobs.contains { $0.status == .queued || $0.status == .cancelling || isRunning($0.status) } }

    private let pipeline: ImportPipeline
    private var worker: Task<Void, Never>?
    private var currentImport: Task<Video, Error>?

    public init(pipeline: ImportPipeline) { self.pipeline = pipeline }

    public func enqueue(_ urls: [URL], profile: any LanguageProfile, model: String, quality: VideoQuality = .smallest) {
        jobs += urls.map { Job(url: $0, profile: profile, model: model, quality: quality) }
        kick()
    }

    /// After a language warning: import it as the language you picked originally.
    public func importAnyway(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].skipsLanguageCheck = true
        jobs[index].status = .queued
        kick()
    }

    /// After a language warning: import it as the language it sounds like.
    public func retry(_ id: UUID, as profile: any LanguageProfile, model: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].profile = profile
        jobs[index].model = model
        jobs[index].status = .queued
        kick()
    }

    /// Cancels a waiting job immediately, or a running one at its next safe point. A cancelled import leaves your
    /// original untouched and removes everything it created.
    public func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch jobs[index].status {
        case .queued, .languageMismatch:
            jobs[index].status = .cancelled
        case .running:
            jobs[index].status = .cancelling
            currentImport?.cancel()
        default:
            break
        }
    }

    private func kick() {
        if worker == nil { worker = Task { await drain() } }
    }

    public func clearFinished() {
        jobs.removeAll { $0.status != .queued && $0.status != .cancelling && !isRunning($0.status) }
    }

    /// Returns once every queued job has finished.
    public func waitUntilIdle() async { await worker?.value }

    private func isRunning(_ status: Status) -> Bool {
        if case .running = status { return true }
        return false
    }

    private func drain() async {
        while let index = jobs.firstIndex(where: { $0.status == .queued }) {
            let job = jobs[index]
            set(job.id, .running(.hashing, 0))
            let update: @Sendable (ImportProgress) -> Void = { [weak self] p in
                Task { @MainActor in self?.report(job.id, p) }
            }
            let work = Task { [pipeline] in
                try await pipeline.importVideo(
                    from: job.url, profile: job.profile, model: job.model,
                    checkLanguage: !job.skipsLanguageCheck, quality: job.quality, progress: update)
            }
            currentImport = work
            // A cancel may have arrived between marking the job running and starting the task.
            if case .cancelling = jobs.first(where: { $0.id == job.id })?.status { work.cancel() }
            let result = await work.result
            currentImport = nil
            switch result {
            case .success:
                set(job.id, .imported)
            case .failure(let error):
                switch error {
                case is CancellationError: set(job.id, .cancelled)
                case ImportError.duplicate: set(job.id, .duplicate)
                case ImportError.languageMismatch(let detected, _, _): set(job.id, .languageMismatch(detected: detected))
                default: set(job.id, .failed(error.localizedDescription))
                }
            }
        }
        worker = nil
    }

    /// Records a progress report: the status, the note, and when the step started (restarted when the model finishes
    /// loading, so the load doesn't count against the time left).
    private func report(_ id: UUID, _ progress: ImportProgress) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let before = jobs[index]
        set(id, .running(progress.stage, progress.fraction))
        guard isRunning(jobs[index].status) else { return }   // a late report from a job that has finished
        var sameStage = false
        if case .running(let stage, _) = before.status, stage == progress.stage { sameStage = true }
        let modelJustLoaded = before.note != nil && progress.note == nil
        if !sameStage || before.stageStartedAt == nil || modelJustLoaded { jobs[index].stageStartedAt = Date() }
        jobs[index].note = progress.note
    }

    /// Late progress updates from a finished job must not overwrite its final status.
    private func set(_ id: UUID, _ status: Status) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if case .running = status, !isRunning(jobs[index].status) && jobs[index].status != .queued { return }
        jobs[index].status = status
    }
}
