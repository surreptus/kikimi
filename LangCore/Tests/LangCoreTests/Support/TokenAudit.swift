import Foundation
@testable import LangCore

/// One token as the audit sees it: what the tokenizer said, whether the import would keep it as a content word, whether the
/// language's dictionary has its lemma (nil when there is no dictionary to ask), and the line it came from.
struct AuditToken: Equatable {
    let surface: String
    let lemma: String
    let pos: PartOfSpeech
    let isCutOff: Bool
    let isContent: Bool
    let hasEntry: Bool?
    let sentence: String
}

/// A kind of tokenizer mistake the audit looks for.
enum AuditSection: String, Codable, CaseIterable {
    case missingEntry, mixedTags, cutOff, looksCutOff, verbNotInfinitive

    var title: String {
        switch self {
        case .missingEntry: "Lemma not in the dictionary"
        case .mixedTags: "Same spelling, different lemma or part of speech"
        case .cutOff: "Flagged as cut off"
        case .looksCutOff: "Looks cut off but is not flagged"
        case .verbNotInfinitive: "Verb whose lemma is the spelling and not an infinitive"
        }
    }
}

struct Suspect: Codable, Equatable {
    let section: AuditSection
    let key: String
    let count: Int
    /// What was seen, for a person to judge ("noun salido ×3, verb salir ×2"). Not part of a suspect's identity.
    let detail: String
    let example: String

    var id: String { "\(section.rawValue)|\(key)" }
}

struct AuditReport: Codable, Equatable {
    var language: String
    var lines: Int
    var tokens: Int
    var contentWords: Int
    /// Content words, and distinct lemmas among them, with no dictionary entry. nil when the dictionary was not checked.
    var noEntryWords: Int?
    var noEntryLemmas: Int?
    var suspects: [Suspect]

    func suspects(in section: AuditSection) -> [Suspect] { suspects.filter { $0.section == section } }
}

struct AuditDiff: Equatable {
    var new: [Suspect]
    var gone: [Suspect]
    var isEmpty: Bool { new.isEmpty && gone.isEmpty }
}

enum TokenAudit {
    /// How a verb's dictionary form ends, per language code. A language not listed has no check (d): Japanese verbs end in
    /// many ways, and MeCab always gives the base form.
    static let infinitiveEndings: [String: [String]] = [
        "es": ["ar", "er", "ir", "ír", "ér", "ár"],
        "fr": ["er", "ir", "re", "oir"],
        "de": ["en", "rn", "ln"],
    ]

    /// Marks a speaker or a subtitle writer leaves after a word that stops short.
    private static let trailingMarks = "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2212}~\u{2026}"

    static func report(language: String, lines: Int, tokens: [AuditToken], infinitiveEndings endings: [String]) -> AuditReport {
        var suspects: [Suspect] = []
        let content = tokens.filter(\.isContent)

        // (a) A content lemma the dictionary does not have. (e) is the same words counted as a whole.
        let missing = content.filter { $0.hasEntry == false }
        suspects += ranked(.missingEntry, missing) { "\($0.lemma) (\($0.pos.rawValue))" }

        // (b) One spelling, more than one reading. All tokens count: a word read as a noun in one line and as a function word
        // in the next is as much a sign as a noun and a verb.
        var byPlainSpelling: [String: [AuditToken]] = [:]
        for token in tokens { byPlainSpelling[token.surface.lowercased(), default: []].append(token) }
        for (spelling, group) in byPlainSpelling {
            let readings = Dictionary(grouping: group) { "\($0.pos.rawValue) \($0.lemma)" }
            guard readings.count > 1 else { continue }
            let order = readings.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            let rarest = order.last!.value[0]
            suspects.append(Suspect(section: .mixedTags, key: spelling, count: group.count,
                                    detail: order.map { "\($0.key) ×\($0.value.count)" }.joined(separator: ", "),
                                    example: rarest.sentence))
        }

        // (c) Cut off: flagged, and words that look it.
        suspects += ranked(.cutOff, tokens.filter(\.isCutOff)) { $0.surface.lowercased() }
        suspects += ranked(.looksCutOff, content.filter { fragmentReason($0) != nil }, detail: { fragmentReason($0) ?? "" }) {
            $0.surface.lowercased()
        }

        // (d) A verb the tagger left as it was written, where that is not how a dictionary form ends.
        if !endings.isEmpty {
            let odd = content.filter { $0.pos == .verb && $0.lemma == $0.surface.lowercased() && !endsLikeInfinitive($0.lemma, endings) }
            suspects += ranked(.verbNotInfinitive, odd) { $0.lemma }
        }

        let checked = content.contains { $0.hasEntry != nil }
        return AuditReport(
            language: language, lines: lines, tokens: tokens.count, contentWords: content.count,
            noEntryWords: checked ? missing.count : nil,
            noEntryLemmas: checked ? Set(missing.map(\.lemma)).count : nil,
            suspects: suspects.sorted(by: ranksBefore))
    }

    /// Why a content word may be a fragment, or nil. Said of an unflagged word: a mark of stopping short right after it
    /// ("pero…", "ha~") when the dictionary has no such word, or one or two letters the dictionary does not have.
    static func fragmentReason(_ token: AuditToken) -> String? {
        guard !token.isCutOff, token.hasEntry != true else { return nil }
        if endsInTrailingMark(token.surface, in: token.sentence) { return "followed by a dash or ellipsis" }
        if token.hasEntry == false, token.surface.count <= 2 { return "one or two letters, no entry" }
        return nil
    }

    /// Whether `word` is followed by a dash, tilde or ellipsis and then no letter or digit (or the end of the line).
    static func endsInTrailingMark(_ word: String, in sentence: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let marks = NSRegularExpression.escapedPattern(for: trailingMarks)
        guard let pattern = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?:[\(marks)]|\\.\\.\\.)+(?![\\p{L}\\p{N}])", options: .caseInsensitive)
        else { return false }
        return pattern.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil
    }

    /// A verb lemma ends like a dictionary form, with or without the reflexive "se" ("irse").
    static func endsLikeInfinitive(_ lemma: String, _ endings: [String]) -> Bool {
        let bare = lemma.hasSuffix("se") && lemma.count > 3 ? String(lemma.dropLast(2)) : lemma
        return endings.contains { bare.hasSuffix($0) }
    }

    // MARK: Ranking and baseline

    /// Counts the tokens that share a key, and keeps the first line each was met in as the example.
    private static func ranked(_ section: AuditSection, _ tokens: [AuditToken], detail: (AuditToken) -> String = { _ in "" },
                               key: (AuditToken) -> String) -> [Suspect] {
        var groups: [String: (count: Int, first: AuditToken)] = [:]
        for token in tokens {
            let k = key(token)
            groups[k] = (((groups[k]?.count) ?? 0) + 1, groups[k]?.first ?? token)
        }
        return groups.map { Suspect(section: section, key: $0.key, count: $0.value.count, detail: detail($0.value.first),
                                    example: $0.value.first.sentence) }
            .sorted(by: ranksBefore)
    }

    /// Most often first; then by section and key, so two runs on the same input give the same order.
    static func ranksBefore(_ a: Suspect, _ b: Suspect) -> Bool {
        (b.count, a.section.rawValue, a.key) < (a.count, b.section.rawValue, b.key)
    }

    /// Suspects the baseline did not have, and suspects it had that are gone. A suspect is the same one when its section and key
    /// match; its count may differ.
    static func diff(_ current: AuditReport, against baseline: AuditReport) -> AuditDiff {
        let before = Set(baseline.suspects.map(\.id)), now = Set(current.suspects.map(\.id))
        return AuditDiff(new: current.suspects.filter { !before.contains($0.id) },
                         gone: baseline.suspects.filter { !now.contains($0.id) })
    }

    // MARK: Text

    /// The report a person reads: the totals, then each section's top suspects.
    static func render(_ report: AuditReport, top: Int = 25) -> String {
        var out = ["Tokenizer audit (\(report.language)): \(report.lines) lines, \(report.tokens) tokens, \(report.contentWords) content words"]
        if let words = report.noEntryWords, let lemmas = report.noEntryLemmas {
            let share = report.contentWords == 0 ? 0 : Double(words) * 100 / Double(report.contentWords)
            out.append("No dictionary entry: \(words) content words (\(String(format: "%.1f", share))%), \(lemmas) distinct lemmas")
        } else {
            out.append("No dictionary entry: not checked, the dictionary file is missing")
        }
        for section in AuditSection.allCases {
            let found = report.suspects(in: section)
            guard !found.isEmpty else { continue }
            out.append("\n\(section.title) (\(found.count))")
            for suspect in found.prefix(top) {
                let note = suspect.detail.isEmpty ? "" : "  [\(suspect.detail)]"
                out.append("  \(String(suspect.count).leftPad(4))  \(suspect.key)\(note)\n        \u{201C}\(suspect.example)\u{201D}")
            }
        }
        return out.joined(separator: "\n")
    }

    static func render(_ diff: AuditDiff, top: Int = 25) -> String {
        if diff.isEmpty { return "Against the baseline: no change in suspects." }
        var out = ["Against the baseline: \(diff.new.count) new, \(diff.gone.count) gone"]
        for (title, list) in [("New", diff.new), ("Gone", diff.gone)] where !list.isEmpty {
            out.append("\n\(title)")
            for suspect in list.prefix(top) {
                out.append("  \(String(suspect.count).leftPad(4))  \(suspect.key)  (\(suspect.section.title.lowercased()))")
            }
            if list.count > top { out.append("  … and \(list.count - top) more") }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Baseline file

    static func encode(_ report: AuditReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    static func decode(_ data: Data) throws -> AuditReport { try JSONDecoder().decode(AuditReport.self, from: data) }
}

private extension String {
    func leftPad(_ width: Int) -> String { String(repeating: " ", count: max(0, width - count)) + self }
}
