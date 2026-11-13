import Foundation
import Observation

extension ImportError: DetailedError {
    public var errorDescription: String? {
        switch self {
        case .duplicate: String(localized: "Already imported.", bundle: .module)
        case .languageMismatch(let detected, let chosen, _):
            String(localized: "This sounds like \(LanguageProfiles.profile(for: detected)?.displayName ?? detected), not \(LanguageProfiles.profile(for: chosen)?.displayName ?? chosen).", bundle: .module)
        case .copyFailed:
            String(localized: "Kikimi couldn't copy this video. Check that the file is still there and that your Mac has free space, then try again.", bundle: .module)
        case .transcriptionFailed(let e): Self.describe(transcription: e)
        case .transcodeFailed:
            String(localized: "Kikimi couldn't prepare this video for your library. Your original is untouched. Check that your Mac has free space, then try again.", bundle: .module)
        case .verificationFailed:
            String(localized: "The library copy of this video didn't turn out right, so Kikimi didn't keep it. Your original is untouched. Try adding it again.", bundle: .module)
        case .libraryMoveFailed:
            String(localized: "Kikimi couldn't put this video in your library. Check that your Mac has free space, then try again.", bundle: .module)
        case .databaseFailed:
            String(localized: "Kikimi couldn't save this video's words. Quit and open Kikimi again, then try again.", bundle: .module)
        case .subtitlesUnusable(let problem): Self.describe(subtitles: problem)
        }
    }

    /// The technical text, for "Show details" and bug reports.
    public var detail: String {
        switch self {
        case .duplicate(let id): "duplicate (existing video \(id.map(String.init) ?? "none"))"
        case .languageMismatch(let detected, let chosen, let confidence): "languageMismatch detected=\(detected) chosen=\(chosen) confidence=\(confidence)"
        case .copyFailed(let e): "copyFailed: \(Problem.rawDetail(of: e))"
        case .transcriptionFailed(let e): "transcriptionFailed: \(Problem(e, fallback: "").detail)"
        case .transcodeFailed(let e): "transcodeFailed: \(Problem(e, fallback: "").detail)"
        case .verificationFailed(let why): "verificationFailed: \(why)"
        case .libraryMoveFailed(let e): "libraryMoveFailed: \(Problem.rawDetail(of: e))"
        case .databaseFailed(let e): "databaseFailed: \(Problem.rawDetail(of: e))"
        case .subtitlesUnusable(let problem): "subtitlesUnusable: \(problem)"
        }
    }

    private static func describe(subtitles problem: SubtitleProblem) -> String {
        switch problem {
        case .unreadable: String(localized: "Kikimi couldn't read that subtitles file. Check that it is an .srt or .vtt file, then try again.", bundle: .module)
        case .noSubtitles: String(localized: "There are no subtitles in that file. Kikimi reads .srt and .vtt files.", bundle: .module)
        case .outsideVideo: String(localized: "These subtitles don't match this video: they all start after it ends. Choose the subtitles for this video.", bundle: .module)
        case .otherLanguage(let name): String(localized: "These subtitles are in \(name), not the language you chose. Choose subtitles in that language, or change the language.", bundle: .module)
        }
    }

    private static func describe(transcription error: Error) -> String {
        switch error {
        case ModelError.notInstalled: String(localized: "The speech model isn't downloaded yet. Download it from Import, then try again.", bundle: .module)
        case AudioExtractionError.noAudioTrack: String(localized: "This file has no audio track. Try a video with sound, or add a subtitles file.", bundle: .module)
        default: String(localized: "Kikimi couldn't turn the speech into text. Try again. If it keeps happening, choose Help > Report a Problem.", bundle: .module)
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
        case failed(Problem)
    }

    public struct Job: Identifiable, Sendable {
        public let id = UUID()
        public let url: URL
        /// A subtitle file to use instead of transcribing, when one was dropped with the video.
        public let subtitles: URL?
        public fileprivate(set) var status: Status = .queued
        public fileprivate(set) var profile: any LanguageProfile
        fileprivate(set) var model: String
        public let quality: VideoQuality
        fileprivate var skipsLanguageCheck = false
        public var fileName: String { url.lastPathComponent }
        /// True when subtitles are read from a file, so there is no transcribing step and no model is needed.
        public var usesSubtitles: Bool { subtitles != nil }
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
        enqueue(urls.map { SubtitlePairing.Item(video: $0, subtitles: nil) }, profile: profile, model: model, quality: quality)
    }

    /// Videos, each with the subtitle file that goes with it if there is one.
    public func enqueue(_ items: [SubtitlePairing.Item], profile: any LanguageProfile, model: String, quality: VideoQuality = .smallest) {
        jobs += items.map { Job(url: $0.video, subtitles: $0.subtitles, profile: profile, model: model, quality: quality) }
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
                    from: job.url, subtitles: job.subtitles, profile: job.profile, model: job.model,
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
                default:
                    set(job.id, .failed(Problem(error, fallback: String(
                        localized: "Kikimi couldn't add this video. Try again. If it keeps happening, choose Help > Report a Problem.", bundle: .module))))
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
