import NaturalLanguage

public struct FrenchProfile: LanguageProfile {
    public init() {}

    public let code = "fr"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "French" }
    public let whisperCode = "fr"
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(language: .french)
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-fr",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
