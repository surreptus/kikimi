import Foundation
import GRDB

/// A list of words you already know, from a text file: one word per line, or the first column of a CSV or TSV (an Anki
/// export, for instance). Marking them known makes coverage believable from the start instead of counting every word
/// as new.
public enum KnownWordList {
    /// The words in `text`, in order and without repeats. Blank lines and lines starting with # are skipped; a line
    /// with tabs, commas or semicolons contributes only its first field; surrounding quotes are removed.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for rawLine in text.replacingOccurrences(of: "\u{FEFF}", with: "").split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let first = line.split(omittingEmptySubsequences: false, whereSeparator: { "\t,;".contains($0) }).first.map(String.init) ?? line
            let word = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespaces))
            if word.isEmpty { continue }
            if seen.insert(word.lowercased()).inserted { words.append(word) }
        }
        return words
    }
}

/// What marking a list of words as known does (or did), in counts.
public struct KnownListReport: Equatable, Sendable {
    /// Distinct words in the list.
    public var listed = 0
    /// Words in your library that become known.
    public var marked = 0
    /// Of those, how many were being learned, and so leave your reviews.
    public var fromLearning = 0
    /// Listed words you already have as known (or finished).
    public var alreadyKnown = 0
    /// Listed words not in your library, so there is nothing to mark. They are not added: they will be new when they
    /// next appear in a video.
    public var notInLibrary = 0
    public init() {}
}

extension LangDatabase {
    /// Marks each listed word known, matching its dictionary form case-insensitively for Latin scripts. Only words
    /// already in this language's library are touched; a word you are learning becomes known, because you said you
    /// know it, and a finished word stays finished. With `dryRun` it only counts.
    @discardableResult
    public func markKnown(lemmas: [String], language: String, dryRun: Bool = false) async throws -> KnownListReport {
        try await writer.write { db in
            var report = KnownListReport()
            var seen = Set<String>()
            for lemma in lemmas {
                let key = lemma.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                report.listed += 1
                let words = try Word
                    .filter(Column("language") == language && (Column("lemma") == lemma || Column("lemma") == key))
                    .fetchAll(db)
                if words.isEmpty { report.notInLibrary += 1; continue }
                var changedAny = false
                for var word in words where word.status == .new || word.status == .learning {
                    changedAny = true
                    report.marked += 1
                    if word.status == .learning { report.fromLearning += 1 }
                    if !dryRun {
                        word.status = .known; word.stage = nil; word.nextReview = nil
                        try word.update(db)
                    }
                }
                if !changedAny { report.alreadyKnown += 1 }
            }
            return report
        }
    }
}
