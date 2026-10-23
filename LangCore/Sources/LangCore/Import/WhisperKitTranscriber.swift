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

    public init(models: ModelManager, chunking: ChunkingMode = .slidingWindow) {
        self.models = models
        self.chunking = chunking
    }

    public func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? {
        let kit = try await kit(for: model)
        let opening = try await AudioExtractor.pcm16kMono(from: mediaURL, limit: 30)
        guard opening.count > Int(AudioExtractor.sampleRate) else { return nil }   // under a second: nothing to judge
        let result = try await kit.detectLangauge(audioArray: opening)
        return LanguageGuess.best(from: result.langProbs)
    }

    public func transcribe(
        mediaURL: URL, whisperCode: String, model: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        let kit = try await kit(for: model)
        let samples = try await AudioExtractor.pcm16kMono(from: mediaURL)
        let total = Double(samples.count) / AudioExtractor.sampleRate
        let options = DecodingOptions(
            task: .transcribe, language: whisperCode, skipSpecialTokens: true,
            chunkingStrategy: chunking == .voiceActivity ? .vad : nil)
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

    private func kit(for model: String) async throws -> WhisperKit {
        if let loaded, loaded.model == model { return loaded.kit }
        guard let folder = await models.installedFolder(for: model) else { throw ModelError.notInstalled(model) }
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, load: true, download: false)
        let kit = try await WhisperKit(config)
        loaded = (model, kit)
        return kit
    }
}
