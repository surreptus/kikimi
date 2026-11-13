import Foundation

/// A language's own corrections to what a tagger says, as data. `NLTaggerTokenizer` applies them and holds no
/// language names. Every rule works on the spelling and the words next to it, so a common word in its common use stays.
public struct TokenRules: Sendable {
    /// Spellings (lower case) that are never a word to learn, and the lemma they get: articles and the like.
    public var functionWords: [String: String]
    /// Spellings that are always an interjection.
    public var interjections: Set<String>
    /// Spellings that are an interjection only when they stand alone between punctuation ("¿vale?"), and a word of the
    /// language elsewhere ("esto vale poco").
    public var standaloneInterjections: Set<String>
    /// Forms of the verb that makes compound tenses ("he", "había"). A word that follows one and ends like a participle is a verb.
    public var auxiliaries: Set<String>
    public var participleEndings: [String]
    /// Words that can stand only before a verb ("yo", "me"). A noun the tagger names right after one is that verb.
    public var verbMarkers: Set<String>
    /// Words that join two verbs ("y", "o").
    public var conjunctions: Set<String>
    /// Whether a word cut off by a hyphen or dash ("hab-") is a fragment, not a word to learn.
    public var marksCutOffWords: Bool
    /// Whether a capitalised word inside a sentence that the tagger names a person, place or organisation is a name, not a noun.
    public var marksNames: Bool

    public init(functionWords: [String: String] = [:], interjections: Set<String> = [], standaloneInterjections: Set<String> = [],
                auxiliaries: Set<String> = [], participleEndings: [String] = [], verbMarkers: Set<String> = [],
                conjunctions: Set<String> = [], marksCutOffWords: Bool = false, marksNames: Bool = false) {
        self.functionWords = functionWords
        self.interjections = interjections
        self.standaloneInterjections = standaloneInterjections
        self.auxiliaries = auxiliaries
        self.participleEndings = participleEndings
        self.verbMarkers = verbMarkers
        self.conjunctions = conjunctions
        self.marksCutOffWords = marksCutOffWords
        self.marksNames = marksNames
    }

    public static let none = TokenRules()
}
