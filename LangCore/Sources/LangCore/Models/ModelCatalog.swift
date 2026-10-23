import Foundation

/// What a person needs to choose a speech model: its size and an honest one-line note.
public struct ModelInfo: Identifiable, Sendable, Equatable {
    public let variant: String
    public let name: String
    /// Download size, from the model repository's own file listing.
    public let downloadBytes: Int64
    public let note: String
    public var id: String { variant }
}

public enum ModelCatalog {
    /// Smallest to largest. Notes say only what was measured here or is widely published, and say when something
    /// was not tested.
    public static let all: [ModelInfo] = [
        ModelInfo(variant: "openai_whisper-tiny", name: "tiny", downloadBytes: 77_000_000,
                  note: "Very fast but rough: it garbled simple sentences in our tests. For trying the app out."),
        ModelInfo(variant: "openai_whisper-base", name: "base", downloadBytes: 147_000_000,
                  note: "Small and quick. Not tested here; expect many mistakes."),
        ModelInfo(variant: "openai_whisper-small", name: "small", downloadBytes: 486_000_000,
                  note: "A middle size. Not tested here."),
        ModelInfo(variant: "openai_whisper-medium", name: "medium", downloadBytes: 1_530_000_000,
                  note: "Good for Spanish: few mistakes on clear speech, and 3 to 5 times faster than real time in our tests on one Apple silicon Mac."),
        ModelInfo(variant: "openai_whisper-large-v3", name: "large-v3", downloadBytes: 3_090_000_000,
                  note: "The most accurate and the usual choice for Japanese, which smaller models handle noticeably worse. Largest and slowest; not benchmarked here."),
    ]

    public static func info(for variant: String) -> ModelInfo? { all.first { $0.variant == variant } }

    /// A readable name for any variant, including ones the catalog doesn't know.
    public static func name(for variant: String) -> String {
        info(for: variant)?.name ?? variant.replacingOccurrences(of: "openai_whisper-", with: "")
    }
}
