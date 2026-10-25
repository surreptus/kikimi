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
