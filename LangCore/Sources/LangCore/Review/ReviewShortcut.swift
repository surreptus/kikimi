import Foundation

/// The keys a review card offers, and when. The hint row under a card is made from these, and each one both shows its key and
/// owns it, so a card can never advertise a key that does nothing (a Shadow card has no sentence buttons, yet the keys must work).
public enum ReviewShortcut: String, CaseIterable, Sendable, Equatable {
    case check, playAgain, sayWord, wordPage, furigana, editSentence, translation

    /// What the keycap says.
    public var key: String {
        switch self {
        case .check: "Return"
        case .playAgain: "⌘R"
        case .sayWord: "W"
        case .wordPage: "I"
        case .furigana: "F"
        case .editSentence: "E"
        case .translation: "T"
        }
    }

    /// The bare key this binds, for the ones that have no button of their own. Return and ⌘R belong to the Check and Play again buttons.
    public var letter: Character? {
        switch self {
        case .sayWord: "w"
        case .wordPage: "i"
        case .furigana: "f"
        case .editSentence: "e"
        case .translation: "t"
        case .check, .playAgain: nil
        }
    }

    /// What is on offer now. Before the answer: only a typed card has any (Check and Play again). After it: say the word if a voice
    /// is installed, the word's page, and, for a card with a sentence, its furigana (Japanese), editing it and (where the Mac can translate) its translation.
    public static func available(
        revealed: Bool, typing: Bool, hasSentence: Bool, canTranslate: Bool, voiceAvailable: Bool, hasFurigana: Bool = false
    ) -> [ReviewShortcut] {
        guard revealed else { return typing ? [.check, .playAgain] : [] }
        var result: [ReviewShortcut] = []
        if voiceAvailable { result.append(.sayWord) }
        result.append(.wordPage)
        if hasSentence, hasFurigana { result.append(.furigana) }
        if hasSentence { result.append(.editSentence) }
        if hasSentence, canTranslate { result.append(.translation) }
        return result
    }

    /// The keys the Review menu may enable. A bare letter would be typed into a text field that has focus, so while one has focus
    /// only the keys that need no bare letter (Check, and Play again with ⌘R) stay.
    public static func menuKeys(offered: [ReviewShortcut], textFieldFocused: Bool) -> [ReviewShortcut] {
        textFieldFocused ? offered.filter { $0.letter == nil } : offered
    }
}
