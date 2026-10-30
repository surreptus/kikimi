import Foundation

public enum TextDirection: Sendable { case leftToRight, rightToLeft }

public struct DisplaySettings: Sendable {
    public var showsReadings: Bool
    public var direction: TextDirection

    public init(showsReadings: Bool = false, direction: TextDirection = .leftToRight) {
        self.showsReadings = showsReadings
        self.direction = direction
    }
}

/// Where a language's dictionary data comes from. The built SQLite file is a bundled resource.
public struct DictionarySource: Sendable {
    public let resourceName: String
    public let attribution: String

    public init(resourceName: String, attribution: String) {
        self.resourceName = resourceName
        self.attribution = attribution
    }
}

/// Everything language-specific. Shared code asks the profile; it never inspects `code`.
public protocol LanguageProfile: Sendable {
    /// App language code, e.g. `es`. Key for `words` and `dictionary` rows.
    var code: String { get }
    var displayName: String { get }
    /// Language code WhisperKit expects.
    var whisperCode: String { get }
    /// Default WhisperKit model variant for this language.
    var defaultModel: String { get }
    var tokenizer: any WordTokenizer { get }
    var contentPOS: Set<PartOfSpeech> { get }
    var dictionarySource: DictionarySource { get }
    /// The built file of per-character data (kanji), for a language whose words are written with them. nil if none.
    var kanjiResourceName: String? { get }
    var display: DisplaySettings { get }
}

extension LanguageProfile {
    public var contentPOS: Set<PartOfSpeech> { [.noun, .verb, .adjective, .adverb] }
    public var kanjiResourceName: String? { nil }
    public var display: DisplaySettings { DisplaySettings() }

    public func contentWords(in text: String) -> [Token] {
        tokenizer.contentTokens(in: text, matching: contentPOS)
    }
}

/// The only place profiles are listed. Adding a language = a new type + one line here.
public enum LanguageProfiles {
    public static let all: [any LanguageProfile] = [SpanishProfile(), FrenchProfile(), GermanProfile(), JapaneseProfile()]

    public static func profile(for code: String) -> (any LanguageProfile)? {
        all.first { $0.code == code }
    }
}
