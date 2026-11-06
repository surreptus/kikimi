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
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(language: .spanish, spellingFixes: SpanishProfile.spellingFixes)

    /// Present-tense forms the tagger gives the wrong verb for (found by running forms of 40 common verbs through it): poder
    /// comes out as podar, salir as salar, sentir as sentar, venir as vengar, creer as crear. Where a spelling is also a
    /// form of the other verb (podáis of podar), the commoner verb wins. Spellings that are also nouns, such as cuenta and
    /// juego, are left alone: the tagger may be right about them in context.
    static let spellingFixes: [String: String] = {
        let forms: [String: [String]] = [
            "poder": ["puedo", "puedes", "puede", "podemos", "podéis", "pueden", "pueda", "puedas", "puedan", "podamos", "podáis"],
            "salir": ["sale", "sales", "salen"],
            "sentir": ["siento", "sientes", "siente", "sienten"],
            "venir": ["vengo", "venga", "vengas", "vengan"],
            "creer": ["creo", "creemos"],
            "dejar": ["dejas"],
            "morir": ["muera", "mueras", "mueran"],
        ]
        return Dictionary(uniqueKeysWithValues: forms.flatMap { lemma, spellings in spellings.map { ($0, lemma) } })
    }()
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-es",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
