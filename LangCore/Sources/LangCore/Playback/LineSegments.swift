import Foundation
import GRDB

/// One piece of a subtitle line: either a word the tokenizer found, or the text between words (spaces, punctuation).
public struct LineSegment: Identifiable, Sendable, Equatable {
    public let id: Int
    public let text: String
    public let token: Token?
}

extension LanguageProfile {
    /// Splits `text` so that joining the segments gives back exactly `text`, with each word marked.
    public func lineSegments(in text: String) -> [LineSegment] {
        var segments: [LineSegment] = []
        var cursor = text.startIndex
        for token in tokenizer.tokens(in: text) {
            guard !token.surface.isEmpty,
                  let range = text.range(of: token.surface, range: cursor..<text.endIndex) else { continue }
            if range.lowerBound > cursor {
                segments.append(LineSegment(id: segments.count, text: String(text[cursor..<range.lowerBound]), token: nil))
            }
            segments.append(LineSegment(id: segments.count, text: String(text[range]), token: token))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(LineSegment(id: segments.count, text: String(text[cursor...]), token: nil))
        }
        return segments
    }
}

/// What to show when hovering a word.
public struct WordHint: Sendable, Equatable {
    /// The word in your list, if it has one (every content word found in an import does).
    public let wordID: Int64?
    public let lemma: String
    public let pos: PartOfSpeech
    public let reading: String?
    /// First meaning, short.
    public let gloss: String?
    public let status: WordStatus?
}

extension DictionaryEntry {
    /// The first sense without its number and part-of-speech tag: "1. (noun) house; home" becomes "house; home".
    public var shortGloss: String {
        let first = gloss.split(separator: "\n").first.map(String.init) ?? gloss
        return first.replacingOccurrences(of: #"^\s*\d+\.\s*(\([^)]*\)\s*)?"#, with: "", options: .regularExpression)
    }
}

extension LangEnvironment {
    public func hint(for token: Token, language: String) async -> WordHint? {
        let entry = try? await database.lookup(language: language, term: token.lemma, limit: 1).first
        let word = try? await database.writer.read { db in
            try Word.filter(Column("language") == language && Column("lemma") == token.lemma && Column("pos") == token.pos.rawValue)
                .fetchOne(db)
        }
        return WordHint(wordID: word?.id, lemma: token.lemma, pos: token.pos, reading: entry?.reading ?? token.reading,
                        gloss: entry?.shortGloss, status: word?.status)
    }
}
