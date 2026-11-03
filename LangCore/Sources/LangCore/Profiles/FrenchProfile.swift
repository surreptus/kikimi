import NaturalLanguage

public struct FrenchProfile: LanguageProfile {
    public init() {}

    public let code = "fr"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "French" }
    public let whisperCode = "fr"
    public let nounArticles = ["m": "le", "f": "la"]

    /// Before a vowel or a silent h the article becomes l', which hides the gender, so the gender is added: l'eau (f).
    public func nounPhrase(headword: String, gender: String?) -> String? {
        guard let article = article(forGender: gender) else { return nil }
        let folded = headword.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if let first = folded.first, "aeiouyh".contains(first), gender == "m" || gender == "f" {
            return "l'\(headword) (\(gender!))"
        }
        return "\(article) \(headword)"
    }
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(language: .french)
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-fr",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
