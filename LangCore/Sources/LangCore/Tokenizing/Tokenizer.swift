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
    /// The speaker stopped in the middle of this word ("hab-"), so it is not a word to learn.
    public let isCutOff: Bool

    public init(surface: String, lemma: String, pos: PartOfSpeech, reading: String? = nil, inflection: String? = nil,
                isCutOff: Bool = false) {
        self.surface = surface
        self.lemma = lemma
        self.pos = pos
        self.reading = reading
        self.inflection = inflection
        self.isCutOff = isCutOff
    }
}

public protocol WordTokenizer: Sendable {
    /// All word tokens in `text`, in order, with lemma and POS. No content filtering.
    func tokens(in text: String) -> [Token]
}

extension WordTokenizer {
    /// Tokens whose POS the profile counts as content words. A word cut off in the middle is not one.
    public func contentTokens(in text: String, matching pos: Set<PartOfSpeech>) -> [Token] {
        tokens(in: text).filter { pos.contains($0.pos) && !$0.isCutOff }
    }
}

/// Apple NaturalLanguage tagger. Parameterised by language, so it contains no per-language branching.
/// Quality varies by language and must be checked per profile.
public struct NLTaggerTokenizer: WordTokenizer {
    private typealias Found = (token: Token, range: Range<String.Index>, spelling: String)

    public let language: NLLanguage
    /// Lemmas the tagger gets wrong in a known, systematic way, mapped to the right one.
    private let lemmaFixes: [String: String]
    /// Words, as written in lower case, whose lemma the tagger gets wrong where the lemma it gives is also a real word
    /// (so `lemmaFixes` would damage the right uses): the lemma to use for that spelling instead.
    private let spellingFixes: [String: String]
    /// Common verbs' spellings, to overrule a verb the tagger names that the spelling cannot be a form of.
    private let verbForms: VerbForms?
    private let rules: TokenRules

    public init(language: NLLanguage, lemmaFixes: [String: String] = [:], spellingFixes: [String: String] = [:],
                verbForms: VerbForms? = nil, rules: TokenRules = .none) {
        self.language = language
        self.lemmaFixes = lemmaFixes
        self.spellingFixes = spellingFixes
        self.verbForms = verbForms
        self.rules = rules
    }

    public func tokens(in text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        var found: [Found] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, range in
            let surface = String(text[range])
            let lemma = (tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? surface).lowercased()
            let spelling = surface.lowercased().precomposedStringWithCanonicalMapping
            var pos = Self.map(tag)
            var chosen = spellingFixes[spelling] ?? lemmaFixes[lemma] ?? lemma
            if let word = rules.functionWords[spelling] {
                pos = .other
                chosen = word
            } else if rules.interjections.contains(spelling)
                        || (rules.standaloneInterjections.contains(spelling) && Self.standsAlone(range, in: text)) {
                pos = .other
                chosen = spelling
            } else if spellingFixes[spelling] == nil, let verbForms {
                let forms = verbForms.lemmas(for: spelling)
                if pos == .verb {
                    // The same spelling as a noun (cuenta) is a word of its own, and the tagger may be right: so only a verb.
                    if let best = forms.first, !forms.contains(chosen) { chosen = best }
                } else if let best = forms.first, verbForms.isOnlyAVerbForm(spelling) {
                    // No word of its own is spelt like this, so whatever the tagger made of it, it is that verb (richtest, which a
                    // tagger can call an adverb).
                    pos = .verb
                    chosen = forms.contains(chosen) ? chosen : best
                }
            }
            if rules.marksNames, pos == .noun, surface.first?.isUppercase == true, !Self.startsSentence(range, in: text),
               let name = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType).0,
               name == .personalName || name == .placeName || name == .organizationName {
                pos = .other
            }
            let cutOff = rules.marksCutOffWords && Self.isCutOff(range, in: text)
            found.append((Token(surface: surface, lemma: chosen, pos: pos, isCutOff: cutOff), range, spelling))
            return true
        }
        correctByNeighbours(&found, in: text)
        return found.map(\.token)
    }

    /// A noun the tagger names because the spelling is also a noun, where the word before shows it is a verb: right after
    /// the auxiliary of a compound tense ("he salido"), after a word that stands only before a verb ("yo cargo"), or in a
    /// list of verbs ("me pongo y cargo"). Only a spelling that `verbForms` knows is changed.
    private func correctByNeighbours(_ found: inout [Found], in text: String) {
        guard let verbForms, found.count > 1 else { return }
        for i in 1..<found.count where found[i].token.pos == .noun {
            guard Self.onlySpaces(between: found[i - 1].range.upperBound, and: found[i].range.lowerBound, in: text),
                  let best = verbForms.lemmas(for: found[i].spelling).first else { continue }
            let before = found[i - 1].spelling
            let isParticiple = rules.auxiliaries.contains(before) && rules.participleEndings.contains { found[i].spelling.hasSuffix($0) }
            let afterMarker = rules.verbMarkers.contains(before)
            let inList = rules.conjunctions.contains(before) && i > 1 && found[i - 2].token.pos == .verb
                && Self.onlySpaces(between: found[i - 2].range.upperBound, and: found[i - 1].range.lowerBound, in: text)
            guard isParticiple || afterMarker || inList else { continue }
            let old = found[i].token
            found[i].token = Token(surface: old.surface, lemma: best, pos: .verb, isCutOff: old.isCutOff)
        }
    }

    private static func onlySpaces(between a: String.Index, and b: String.Index, in text: String) -> Bool {
        text[a..<b].allSatisfy(\.isWhitespace)
    }

    private static let dashes: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2013}", "\u{2014}"]

    /// A word that is cut off: a hyphen or dash touches its end, and no letter or digit follows ("no hab- es", "para-").
    private static func isCutOff(_ range: Range<String.Index>, in text: String) -> Bool {
        guard range.upperBound < text.endIndex, dashes.contains(text[range.upperBound]) else { return false }
        let rest = text[range.upperBound...].drop { dashes.contains($0) }
        guard let next = rest.first else { return true }
        return !(next.isLetter || next.isNumber)
    }

    /// Whether the word has punctuation, or the edge of the text, on both sides ("¿vale?", "Vale,").
    private static func standsAlone(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].last { !$0.isWhitespace }
        let after = text[range.upperBound...].first { !$0.isWhitespace }
        func edge(_ c: Character?) -> Bool { c.map { $0.isPunctuation || $0.isSymbol } ?? true }
        return edge(before) && edge(after)
    }

    private static let sentenceOpeners: Set<Character> = [".", "!", "?", "¿", "¡", "…", ":", "\"", "«", "“", "-", "–", "—"]

    /// Whether only punctuation, or nothing, comes before the word in its sentence, where a capital says nothing.
    private static func startsSentence(_ range: Range<String.Index>, in text: String) -> Bool {
        guard let before = text[..<range.lowerBound].last(where: { !$0.isWhitespace }) else { return true }
        return sentenceOpeners.contains(before)
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
