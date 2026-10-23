import Foundation

public enum ImportStage: String, Sendable {
    case hashing, staging, detectingLanguage, transcribing, transcoding, verifying, extractingAudio, saving
}

public struct ImportProgress: Sendable {
    public let stage: ImportStage
    /// 0...1 within the stage.
    public let fraction: Double
}

public typealias ProgressHandler = @Sendable (ImportProgress) -> Void

public struct TranscriptSegment: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start; self.end = end; self.text = text
    }
}

/// Failures leave the user's original file untouched; the pipeline only ever deletes its own staging and library output.
public enum ImportError: Error {
    case duplicate(existingVideoID: Int64?)
    /// The audio sounds like another supported language (`detected` is that profile's code).
    case languageMismatch(detected: String, chosen: String, confidence: Double)
    case copyFailed(Error)
    case transcriptionFailed(Error)
    case transcodeFailed(Error)
    case verificationFailed(String)
    case audioExportFailed(Error)
    case libraryMoveFailed(Error)
    case databaseFailed(Error)
}

/// The language Whisper thinks is being spoken, as a WhisperKit language code with a 0...1 confidence.
public struct LanguageGuess: Equatable, Sendable {
    public static func == (a: LanguageGuess, b: LanguageGuess) -> Bool { a.code == b.code && a.confidence == b.confidence }

    public let code: String
    public let confidence: Double
    /// The best few candidates and their normalised scores, for diagnosing odd results.
    public let runnersUp: [String: Double]

    public init(code: String, confidence: Double, runnersUp: [String: Double] = [:]) {
        self.code = code; self.confidence = confidence; self.runnersUp = runnersUp
    }

    /// Picks the most likely language from WhisperKit's scores, which may be probabilities or log-probabilities.
    /// WhisperKit actually returns just the winner with its own log-probability, so a lone score is that
    /// language's confidence as it stands; with several scores they are normalised against each other.
    public static func best(from scores: [String: Float]) -> LanguageGuess? {
        guard let top = scores.max(by: { $0.value < $1.value }) else { return nil }
        if scores.count == 1 {
            let p = top.value <= 0 ? exp(Double(top.value)) : Double(top.value)
            return LanguageGuess(code: top.key, confidence: min(1, max(0, p)), runnersUp: [top.key: min(1, max(0, p))])
        }
        let logs = scores.values.contains { $0 < 0 }
        let weights = scores.mapValues { logs ? exp(Double($0)) : Double($0) }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return nil }
        let top3 = weights.sorted { $0.value > $1.value }.prefix(3)
        return LanguageGuess(code: top.key, confidence: (weights[top.key] ?? 0) / total,
                             runnersUp: Dictionary(uniqueKeysWithValues: top3.map { ($0.key, $0.value / total) }))
    }
}

public protocol Transcriber: Sendable {
    /// What language is spoken in the first seconds of `mediaURL`? nil if the transcriber can't tell.
    func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess?

    /// Transcribes the audio of `mediaURL`. `model` is a WhisperKit model variant.
    func transcribe(
        mediaURL: URL, whisperCode: String, model: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment]
}

public protocol MediaTranscoder: Sendable {
    func compactVideo(
        source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws
    func extractAAC(source: URL, destination: URL) async throws
}

extension Transcriber {
    public func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? { nil }
}
