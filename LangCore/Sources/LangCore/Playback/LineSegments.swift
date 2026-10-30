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
    /// Where it is in the review stages, for a word being learned.
    public let stage: SRSStage?
    /// The word's other readings (月 is つき, and also がつ), after `reading`.
    public var otherReadings: [String] = []
}

extension [DictionaryEntry] {
    /// The distinct readings of the entries spelled `headword`, in dictionary order (the commoner first), with
    /// `first` leading when given. A spelling can have several (月: つき, がつ, げつ); `limit` keeps a kanji with
    /// a dozen from filling the line.
    public func readings(of headword: String, first: String? = nil, limit: Int = 4) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for reading in [first] + filter({ $0.headword == headword }).map(\.reading) {
            if let reading, seen.insert(reading).inserted { result.append(reading) }
        }
        return [String](result.prefix(limit))
    }
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
        // Several entries can share a spelling (秋 is あき, "autumn", and also とき). The tokenizer read the word in
        // context, so when one of the entries has that reading it is the one meant; otherwise take the first.
        let entries = (try? await database.lookup(language: language, term: token.lemma, limit: 8)) ?? []
        let entry = entries.first { token.reading != nil && $0.reading == token.reading } ?? entries.first
        let word = try? await database.writer.read { db in
            try Word.filter(Column("language") == language && Column("lemma") == token.lemma && Column("pos") == token.pos.rawValue)
                .fetchOne(db)
        }
        let reading = entry?.reading ?? token.reading
        return WordHint(wordID: word?.id, lemma: token.lemma, pos: token.pos, reading: reading,
                        gloss: entry?.shortGloss, status: word?.status, stage: word?.stage,
                        otherReadings: entries.readings(of: token.lemma, first: reading).filter { $0 != reading })
    }
}

extension LanguageProfile {
    /// Dictionary forms of the content words in `term`: corremos gives correr, 食べた gives 食べる.
    public func lemmas(of term: String) -> [String] {
        var seen = Set<String>()
        return contentWords(in: term).map(\.lemma).filter { seen.insert($0).inserted }
    }
}

extension LangEnvironment {
    /// Dictionary entries for a typed word, falling back to its dictionary form when the form itself has no entry.
    public func lookupWord(_ term: String, profile: any LanguageProfile, limit: Int = 5) async -> [DictionaryEntry] {
        let exact = (try? await database.lookup(language: profile.code, term: term, limit: limit)) ?? []
        guard exact.isEmpty else { return exact }
        var found: [DictionaryEntry] = []
        for lemma in profile.lemmas(of: term) where lemma != term {
            let entries = (try? await database.lookup(language: profile.code, term: lemma, limit: limit)) ?? []
            found += entries.filter { entry in !found.contains { $0.id == entry.id } }
        }
        return Array(found.prefix(limit))
    }

    /// Your words matching `term`; when none do, the words for its dictionary forms ("corremos" finds "correr").
    public func searchWords(
        _ term: String, profile: any LanguageProfile, status: WordStatus? = nil, pos: PartOfSpeech? = nil
    ) async -> [WordRow] {
        let direct = (try? await database.words(language: profile.code, search: term, status: status, pos: pos)) ?? []
        guard direct.isEmpty, !term.trimmingCharacters(in: .whitespaces).isEmpty else { return direct }
        var found: [WordRow] = []
        for lemma in profile.lemmas(of: term) where lemma != term {
            let rows = (try? await database.words(language: profile.code, search: lemma, status: status, pos: pos)) ?? []
            found += rows.filter { row in !found.contains { $0.id == row.id } }
        }
        return found
    }
}
