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
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(
        language: .spanish, spellingFixes: SpanishProfile.spellingFixes, verbForms: VerbForms(resource: "dictionary-es"))

    /// Spellings that two common verbs share, where the dictionary's table of verb forms (`VerbForms`) cannot choose and
    /// the tagger picks the wrong one: siento is sentir ("lo siento"), not sentar. The table overrules the rest of the
    /// tagger's mistakes by itself (puede read as podar, sale as salar, venga as vengar, creo as crear), found by running
    /// forms of 40 common verbs through it.
    static let spellingFixes: [String: String] = [
        "siento": "sentir", "sientes": "sentir", "siente": "sentir", "sienten": "sentir",
    ]
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-es",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
