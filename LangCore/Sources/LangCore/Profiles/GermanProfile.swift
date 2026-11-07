import NaturalLanguage

public struct GermanProfile: LanguageProfile {
    public init() {}

    public let code = "de"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "German" }
    public var flagRegion: String? { "DE" }
    public var keyboardKeywords: [String] { ["German"] }
    public let whisperCode = "de"
    public let nounArticles = ["m": "der", "f": "die", "n": "das"]
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(
        language: .german,
        // For "kann", "musst" and "darf" the tagger answers with the ASCII spelling, which no dictionary has.
        lemmaFixes: ["koennen": "können", "muessen": "müssen", "duerfen": "dürfen"],
        verbForms: VerbForms(resource: "dictionary-de"))
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-de",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
