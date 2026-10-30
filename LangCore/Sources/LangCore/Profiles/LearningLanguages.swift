import Foundation

/// The languages the person is learning, chosen on first launch and changeable in Settings. The sidebar and Settings
/// show only these; nothing else about a language changes, so a language dropped here keeps its words and videos.
public struct LearningLanguages: @unchecked Sendable {
    public static let key = "learningLanguages"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The chosen language codes in registry order, or nil if the person has not chosen yet.
    public var codes: [String]? {
        get {
            guard let stored = defaults.stringArray(forKey: Self.key) else { return nil }
            let known = LanguageProfiles.all.map(\.code).filter(stored.contains)
            return known.isEmpty ? nil : known
        }
        nonmutating set {
            // Choosing none is not a choice: the app needs a language to open on.
            let known = LanguageProfiles.all.map(\.code).filter { newValue?.contains($0) == true }
            defaults.set(known.isEmpty ? nil : known, forKey: Self.key)
        }
    }

    public var profiles: [any LanguageProfile] {
        guard let codes else { return LanguageProfiles.all }
        return LanguageProfiles.all.filter { codes.contains($0.code) }
    }
}
