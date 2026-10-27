import Foundation
import NaturalLanguage

public enum PartOfSpeech: String, Codable, Sendable {
    case noun, verb, adjective, adverb, other
}

public struct Token: Equatable, Sendable {
    public let surface: String
    public let lemma: String
    public let pos: PartOfSpeech
    /// How `surface` is read, in hiragana, when it contains kanji (shown as furigana). nil otherwise.
    public let reading: String?
    /// The form this word is in, when the tokenizer says (Japanese: IPADIC's 活用形, such as 未然形). nil for the
    /// dictionary form and for words that don't inflect.
    public let inflection: String?

    public init(surface: String, lemma: String, pos: PartOfSpeech, reading: String? = nil, inflection: String? = nil) {
        self.surface = surface
        self.lemma = lemma
        self.pos = pos
        self.reading = reading
        self.inflection = inflection
    }
}

public protocol WordTokenizer: Sendable {
    /// All word tokens in `text`, in order, with lemma and POS. No content filtering.
    func tokens(in text: String) -> [Token]
}

extension WordTokenizer {
    /// Tokens whose POS the profile counts as content words.
    public func contentTokens(in text: String, matching pos: Set<PartOfSpeech>) -> [Token] {
        tokens(in: text).filter { pos.contains($0.pos) }
    }
}

/// Apple NaturalLanguage tagger. Parameterised by language, so it contains no per-language branching.
/// Quality varies by language and must be checked per profile.
public struct NLTaggerTokenizer: WordTokenizer {
    public let language: NLLanguage

    public init(language: NLLanguage) { self.language = language }

    public func tokens(in text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        var result: [Token] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, range in
            let surface = String(text[range])
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            result.append(Token(
                surface: surface,
                lemma: (lemma ?? surface).lowercased(),
                pos: Self.map(tag)))
            return true
        }
        return result
    }

    private static func map(_ tag: NLTag?) -> PartOfSpeech {
        switch tag {
        case .noun: .noun
        case .verb: .verb
        case .adjective: .adjective
        case .adverb: .adverb
        default: .other
        }
    }
}
