import Foundation
import Translation

/// When translations are shown under the subtitle lines.
public enum TranslationDisplay: String, CaseIterable, Sendable {
    case off
    /// Hidden until you ask for a line's translation. Showing it always would invite reading over listening.
    case onRequest
    case always
}

/// The chosen display and target language, kept in the app's settings.
public struct TranslationPreferences: @unchecked Sendable {
    public static let displayKey = "translationDisplay"
    public static let targetKey = "translationTarget"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var display: TranslationDisplay {
        get { defaults.string(forKey: Self.displayKey).flatMap(TranslationDisplay.init(rawValue:)) ?? .onRequest }
        nonmutating set { defaults.set(newValue == .onRequest ? nil : newValue.rawValue, forKey: Self.displayKey) }
    }

    /// The language to translate into: the one chosen, else the Mac's own.
    public var target: String {
        get { defaults.string(forKey: Self.targetKey) ?? Self.systemLanguage }
        nonmutating set { defaults.set(newValue == Self.systemLanguage ? nil : newValue, forKey: Self.targetKey) }
    }

    public static var systemLanguage: String { Locale.current.language.minimalIdentifier }
}

/// A language the system can translate between, for choosing a target.
public struct TranslationLanguage: Identifiable, Equatable, Sendable {
    public let id: String       // such as "en" or "zh-Hans"
    public let name: String     // in the reader's language

    public init(id: String, name: String) { self.id = id; self.name = name }

    /// The languages macOS can translate, sorted by name.
    public static func supported() async -> [TranslationLanguage] {
        let ids = await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
        return Set(ids).map { id in
            TranslationLanguage(id: id, name: Locale.current.localizedString(forIdentifier: id)?.localizedCapitalized ?? id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
