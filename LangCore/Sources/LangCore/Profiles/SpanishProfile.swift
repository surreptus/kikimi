import NaturalLanguage

public struct SpanishProfile: LanguageProfile {
    public init() {}

    public let code = "es"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "Spanish" }
    public let whisperCode = "es"
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(language: .spanish)
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-es",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
