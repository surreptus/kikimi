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
    public var contentPOS: Set<PartOfSpeech> { [.noun, .verb, .adjective, .adverb, .conjunction] }
    public let defaultModel = "openai_whisper-medium"
    public let tokenizer: any WordTokenizer = NLTaggerTokenizer(
        language: .spanish, spellingFixes: SpanishProfile.spellingFixes, verbForms: VerbForms(resource: "dictionary-es"),
        rules: SpanishProfile.rules)

    static let rules = TokenRules(
        // The table of verb forms knows "unas" only as a form of unir, so it overruled the tagger's "article".
        functionWords: ["unas": "un", "unos": "un"],
        interjections: ["ey"],
        // "vale" is a verb too ("esto vale poco"), so only when it stands alone ("¿vale?").
        standaloneInterjections: ["vale"],
        auxiliaries: ["he", "has", "ha", "hemos", "habéis", "han", "había", "habías", "habíamos", "habíais", "habían",
                      "haya", "hayas", "hayamos", "hayáis", "hayan", "habré", "habrás", "habrá", "habremos", "habrán",
                      "habría", "habrías", "habríamos", "habrían", "hube", "hubo", "hubiera", "hubiese"],
        participleEndings: ["ado", "ido", "to", "cho"],
        verbMarkers: ["yo", "me", "te", "se", "nos"],
        conjunctions: ["y", "e", "o", "pero"],
        // Left out: "como" (also comer), "si" and "que" (too frequent to teach), "y" and "o" (a child knows them), and the
        // questions "cuándo" and "porqué", which are other words.
        learnableConjunctions: ["porque", "pero", "aunque", "mientras", "sino", "pues", "cuando"],
        // "para" is the verb parar only after a subject or "se" ("el coche se para"); a noun or "el tren" before it is
        // ambiguous, and the tagger decides there. Cut off ("pues para-"), the tagger reads it as a number named parar.
        prepositionsSpelledAsVerbs: ["para"],
        subjects: ["yo", "tú", "él", "ella", "usted", "nosotros", "nosotras", "vosotros", "vosotras", "ellos", "ellas", "ustedes"],
        marksCutOffWords: true,
        marksNames: true)

    /// Spellings that two common verbs share, where the dictionary's table of verb forms (`VerbForms`) cannot choose and
    /// the tagger picks the wrong one: siento is sentir ("lo siento"), not sentar. The table overrules the rest of the
    /// tagger's mistakes by itself (puede read as podar, sale as salar, venga as vengar, creo as crear), found by running
    /// forms of 40 common verbs through it.
    static let spellingFixes: [String: String] = [
        "siento": "sentir", "sientes": "sentir", "siente": "sentir", "sienten": "sentir",
        // Subtitles often leave the accent off; no other word is spelt like these.
        "tia": "tía", "tias": "tía", "tio": "tío", "tios": "tío",
    ]
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-es",
        attribution: "Wiktionary via kaikki.org (CC BY-SA 4.0)")
}
