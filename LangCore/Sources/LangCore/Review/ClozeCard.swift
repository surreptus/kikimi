import Foundation

/// How a review card asks: the word and its meaning ("meaning"), or a sentence from your videos with the word
/// blanked, for you to recall ("cloze").
public enum ReviewStyle: String, CaseIterable, Sendable {
    case meaning
    case cloze
}

/// The chosen style for each language, kept in the app's settings.
public struct ReviewStylePreference: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func style(for profile: any LanguageProfile) -> ReviewStyle {
        defaults.string(forKey: key(profile)).flatMap(ReviewStyle.init(rawValue:)) ?? .meaning
    }

    public func setStyle(_ style: ReviewStyle, for profile: any LanguageProfile) {
        defaults.set(style == .meaning ? nil : style.rawValue, forKey: key(profile))
    }

    private func key(_ profile: any LanguageProfile) -> String { "reviewStyle.\(profile.code)" }
}

/// A review card as a fill-in-the-blank: the example sentence with the word as it appears there taken out.
public struct ClozeCard: Equatable, Sendable {
    public static let blank = "______"

    public let before: String
    /// The word as it appears in the sentence (so it may be an inflected form of the card's word).
    public let answer: String
    public let after: String
    /// What to think of: the meaning, plus the dictionary form when the sentence has a different form, or the
    /// reading in a language that has one. Never the answer itself.
    public let hint: String

    public var prompt: String { before + Self.blank + after }

    /// nil when the card has no sentence, or the word can't be found in it: the card is then asked the usual way.
    public static func make(from card: ReviewCard, showsReading: Bool) -> ClozeCard? {
        guard let example = card.example, !example.surface.isEmpty,
              let range = find(example.surface, in: example.text) else { return nil }
        let answer = String(example.text[range])
        var parts: [String] = []
        if showsReading, let reading = card.entries.first?.reading, !reading.isEmpty, reading != answer {
            parts.append(reading)
        } else if !showsReading, answer.lowercased() != card.word.lemma.lowercased() {
            parts.append(card.word.lemma)
        }
        if let gloss = card.entries.first?.gloss, let short = shortGloss(gloss) { parts.append(short) }
        return ClozeCard(
            before: String(example.text[..<range.lowerBound]), answer: answer,
            after: String(example.text[range.upperBound...]), hint: parts.joined(separator: " · "))
    }

    /// The first meaning, without its number or part of speech, cut short: "1. (noun) house; home" becomes "house".
    static func shortGloss(_ gloss: String, limit: Int = 60) -> String? {
        var line = gloss.split(separator: "\n").first.map(String.init) ?? gloss
        if let match = line.range(of: #"^\d+\.\s*(\([^)]*\)\s*)?"#, options: .regularExpression) { line.removeSubrange(match) }
        if let semicolon = line.firstIndex(of: ";") { line = String(line[..<semicolon]) }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// The first place `surface` stands as a word of its own. In a language written without spaces any match counts.
    private static func find(_ surface: String, in text: String) -> Range<String.Index>? {
        let unspaced = surface.unicodeScalars.contains { $0.value >= 0x2E80 }
        var searchStart = text.startIndex
        while let range = text.range(of: surface, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            if unspaced { return range }
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let isWord = !(before?.isLetter ?? false) && !(before?.isNumber ?? false)
                && !(after?.isLetter ?? false) && !(after?.isNumber ?? false)
            if isWord { return range }
            searchStart = text.index(after: range.lowerBound)
        }
        return nil
    }
}
