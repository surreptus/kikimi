import Foundation
import WhisperKit

/// How long audio is split for decoding.
public enum ChunkingMode: Sendable {
    /// Splits at detected speech. About 2x faster, but measured on a 73 s Spanish passage it skipped the first 15 s.
    case voiceActivity
    /// Whisper's own 30 s windows. Slower, and it didn't drop speech in the same test.
    case slidingWindow
}

/// Transcribes with WhisperKit using models the `ModelManager` has already downloaded.
public actor WhisperKitTranscriber: Transcriber {
    private let models: ModelManager
    private let chunking: ChunkingMode
    private var loaded: (model: String, kit: WhisperKit)?
    /// The model takes 1.5 to 3 GB, so it is let go after a while without use. Loading it again is quicker than the
    /// first time, because the compiled form is cached.
    private let idleDelay: Duration
    private lazy var idle = IdleRelease(after: idleDelay) { [weak self] in await self?.releaseModel() }

    public init(models: ModelManager, chunking: ChunkingMode = .slidingWindow, releaseAfter: Duration = .seconds(120)) {
        self.models = models
        self.chunking = chunking
        self.idleDelay = releaseAfter
    }

    private func releaseModel() { loaded = nil }

    public func isModelLoaded(_ model: String) async -> Bool { loaded?.model == model }

    public func loadModel(_ model: String) async throws {
        try await idle.use { _ = try await self.kit(for: model) }
    }

    public func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? {
        try await idle.use {
            let kit = try await self.kit(for: model)
            let opening = try await AudioExtractor.pcm16kMono(from: mediaURL, limit: 30)
            guard opening.count > Int(AudioExtractor.sampleRate) else { return nil }   // under a second: nothing to judge
            let result = try await kit.detectLangauge(audioArray: opening)
            return LanguageGuess.best(from: result.langProbs)
        }
    }

    public func transcribe(
        mediaURL: URL, whisperCode: String, model: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        try await idle.use {
            let kit = try await self.kit(for: model)
            let samples = try await AudioExtractor.pcm16kMono(from: mediaURL)
            let total = Double(samples.count) / AudioExtractor.sampleRate
            let options = DecodingOptions(
                task: .transcribe, language: whisperCode, skipSpecialTokens: true,
                chunkingStrategy: self.chunking == .voiceActivity ? .vad : nil)
            let results = try await kit.transcribe(
                audioArray: samples, decodeOptions: options,
                segmentCallback: { segments in
                    if let last = segments.last, total > 0 { progress(min(1, Double(last.end) / total)) }
                })
            let raw = results.flatMap(\.segments).map {
                TranscriptSegment(start: Double($0.start), end: Double($0.end), text: $0.text)
            }
            return TranscriptCleaner.clean(raw, audioDuration: total)
        }
    }

    private func kit(for model: String) async throws -> WhisperKit {
        guard let folder = await models.installedFolder(for: model) else {
            if loaded?.model == model { loaded = nil }   // it was removed: release the memory it was holding
            throw ModelError.notInstalled(model)
        }
        if let loaded, loaded.model == model { return loaded.kit }
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, load: true, download: false)
        let kit = try await WhisperKit(config)
        loaded = (model, kit)
        return kit
    }
}
