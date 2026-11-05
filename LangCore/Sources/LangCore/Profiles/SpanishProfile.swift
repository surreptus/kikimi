import NaturalLanguage

public struct SpanishProfile: LanguageProfile {
    public init() {}

    public let code = "es"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "Spanish" }
    public var flagRegion: String? { "ES" }
    public var keyboardKeywords: [String] { ["Spanish"] }
    public let whisperCode = "es"
    public let nounArticles = ["m": "el", "f": "la"]

    /// A feminine noun that starts with a stressed "a" takes "el" (el agua), and which ones do isn't in the data, so any
    /// feminine noun starting with "a" or "ha" is shown with its gender instead of an article that may be wrong.
    public func nounPhrase(headword: String, gender: String?) -> String? {
        guard let article = article(forGender: gender) else { return nil }
        let folded = headword.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if gender == "f", folded.hasPrefix("a") || folded.hasPrefix("ha") { return "\(headword) (f)" }
        return "\(article) \(headword)"
    }
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(language: .spanish)
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-es",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
