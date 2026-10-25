import Foundation

public enum ImportStage: String, Sendable, CaseIterable {
    case hashing, staging, detectingLanguage, transcribing, transcoding, verifying, saving

    /// Whether the step reports how far along it is. Only transcribing and compressing do; the others have no
    /// measurable progress, so the UI shows a bar that just moves instead of one stuck at empty.
    public var reportsProgress: Bool { self == .transcribing || self == .transcoding }

    /// The steps an import goes through, in order. The language check is left out when it was skipped (an import
    /// the user chose to go ahead with anyway), so "3 of 7" is true.
    public static func steps(checkingLanguage: Bool) -> [ImportStage] {
        allCases.filter { checkingLanguage || $0 != .detectingLanguage }
    }

    /// "3 of 7": this step's place in the import.
    public func position(checkingLanguage: Bool) -> (number: Int, of: Int) {
        let steps = Self.steps(checkingLanguage: checkingLanguage)
        return ((steps.firstIndex(of: self) ?? 0) + 1, steps.count)
    }
}

/// Something worth saying about a step beyond its name.
public enum ImportNote: Sendable, Equatable {
    /// The speech model is being loaded into memory. The first time on a Mac it is also compiled for it, which can
    /// take minutes, and nothing else is reported meanwhile.
    case loadingModel
}

public struct ImportProgress: Sendable {
    public let stage: ImportStage
    /// 0...1 within the stage.
    public let fraction: Double
    public let note: ImportNote?

    public init(stage: ImportStage, fraction: Double, note: ImportNote? = nil) {
        self.stage = stage; self.fraction = fraction; self.note = note
    }
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

    /// Whether `model` is loaded and ready, and a way to load it. These let the pipeline tell the user when the
    /// wait is the model loading; the defaults say "always ready".
    func isModelLoaded(_ model: String) async -> Bool
    func loadModel(_ model: String) async throws
}

public protocol MediaTranscoder: Sendable {
    func compactVideo(
        source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

extension Transcriber {
    public func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? { nil }
    /// Whether `model` is ready to use right now. A transcriber with nothing to load is always ready.
    public func isModelLoaded(_ model: String) async -> Bool { true }
    /// Loads `model` ahead of its first use, so the pipeline can say it is doing so.
    public func loadModel(_ model: String) async throws {}
}

