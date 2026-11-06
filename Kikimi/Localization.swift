import LangCore
import SwiftUI

/// User-facing text that is built in code rather than written in a view. Every piece of it goes through
/// `String(localized:)` (or a `LocalizedStringKey` in a view), so a translation can replace it without a code change.

/// A string with automatic grammar agreement, such as "^[\(count) word](inflect: true)" ("1 word", "2 words").
/// `String(localized:)` leaves the markup in place; going through an attributed string resolves it.
func inflected(_ value: String.LocalizationValue) -> String {
    String(AttributedString(localized: value).characters)
}

/// "Spanish and Japanese", in the reader's language.
func listed(_ items: [String]) -> String { items.formatted(.list(type: .and)) }

extension WordStatus {
    var title: String {
        switch self {
        case .new: String(localized: "New")
        case .learning: String(localized: "Learning")
        case .known: String(localized: "Known")
        case .finished: String(localized: "Finished")
        case .ignored: String(localized: "Ignored")
        }
    }
}

extension ReviewPrompt {
    var title: String {
        switch self {
        case .word: String(localized: "Word and meaning")
        case .cloze: String(localized: "Fill in the word")
        case .sentence: String(localized: "Sentence from your videos")
        }
    }

    /// A word or two for a segment of the picker; `title` is the full name, which VoiceOver uses.
    var shortTitle: String {
        switch self {
        case .word: String(localized: "Meaning")
        case .cloze: String(localized: "Fill in")
        case .sentence: String(localized: "Sentence")
        }
    }

    var symbol: String {
        switch self {
        case .word: "character.book.closed"
        case .cloze: "ellipsis.rectangle"
        case .sentence: "ear"
        }
    }
}

extension ReviewAnswer {
    var title: String {
        switch self {
        case .check: String(localized: "Listen, then check")
        case .type: String(localized: "Type what you hear")
        case .speak: String(localized: "Say the sentence aloud")
        }
    }

    var shortTitle: String {
        switch self {
        case .check: String(localized: "Listen")
        case .type: String(localized: "Type")
        case .speak: String(localized: "Shadow")
        }
    }

    var symbol: String {
        switch self {
        case .check: "eye"
        case .type: "keyboard"
        case .speak: "mic"
        }
    }
}

extension ReviewStyle {
    /// One line on what the cards ask, shown under the choice.
    var summary: String {
        switch self {
        case .meaning: String(localized: "See the word and recall its meaning.")
        case .cloze: String(localized: "Recall the missing word in a sentence from your videos.")
        case .listening: String(localized: "Hear a sentence from your videos, then check what it said.")
        case .dictation: String(localized: "Hear a short sentence from your videos and type it. You see what you missed.")
        case .shadowing: String(localized: "Hear a short sentence from your videos, say it aloud and play yourself beside the original. Uses the microphone.")
        }
    }
}

extension PartOfSpeech {
    var title: String {
        switch self {
        case .noun: String(localized: "Noun")
        case .verb: String(localized: "Verb")
        case .adjective: String(localized: "Adjective")
        case .adverb: String(localized: "Adverb")
        case .other: String(localized: "Other")
        }
    }
}
