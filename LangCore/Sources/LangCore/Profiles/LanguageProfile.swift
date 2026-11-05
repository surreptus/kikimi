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
    /// The country whose flag stands for the language on the welcome page (ISO 3166, e.g. `ES`), or nil for none.
    var flagRegion: String? { get }
    /// Language code WhisperKit expects.
    var whisperCode: String { get }
    /// Default WhisperKit model variant for this language.
    var defaultModel: String { get }
    var tokenizer: any WordTokenizer { get }
    var contentPOS: Set<PartOfSpeech> { get }
    var dictionarySource: DictionarySource { get }
    /// The built file of per-character data (kanji), for a language whose words are written with them. nil if none.
    var kanjiResourceName: String? { get }
    /// The article that goes with each gender letter ("m", "f", "n"), for a language whose nouns have one. Empty if none.
    var nounArticles: [String: String] { get }
    /// The pieces a typed copy of a line is compared in, and the most a line may have to be offered for typing.
    func dictationUnits(in text: String) -> [String]
    var dictationLimit: Int { get }
    /// What goes between the pieces when they are shown again: a space, or nothing in a language written without them.
    var dictationSeparator: String { get }
    /// A noun as a learner should meet it, with its article ("das Buch"), or nil if there is nothing to add.
    /// A profile overrides it where the plain article would be wrong (French "l'eau", Spanish "el agua").
    func nounPhrase(headword: String, gender: String?) -> String?
    var display: DisplaySettings { get }
}

extension LanguageProfile {
    public var flagRegion: String? { nil }
    /// The language's name in itself ("Español"), so a learner can find it whatever language the Mac is set to.
    public var nativeName: String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? displayName
    }
    public var contentPOS: Set<PartOfSpeech> { [.noun, .verb, .adjective, .adverb] }
    public var kanjiResourceName: String? { nil }
    public var nounArticles: [String: String] { [:] }

    public func nounPhrase(headword: String, gender: String?) -> String? {
        article(forGender: gender).map { "\($0) \(headword)" }
    }

    /// "el", "der", or "le / la" for a word with two genders; nil when the word has none or the language has no articles.
    public func article(forGender gender: String?) -> String? {
        let articles = (gender ?? "").split(separator: ",").compactMap { nounArticles[String($0)] }
        return articles.isEmpty ? nil : articles.joined(separator: " / ")
    }
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
