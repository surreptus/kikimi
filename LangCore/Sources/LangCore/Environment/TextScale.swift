import Foundation

/// How large the app's text is: a step up from the usual size, for people who want it bigger. macOS has no system text-size
/// setting that apps follow, so the app scales its own text by this factor. There is no step below the usual size, since
/// the smallest text is already as small as it can be and stay readable (12 pt).
public enum TextScale: String, CaseIterable, Sendable {
    case standard, large, larger, largest

    public static let key = "textScale"

    public var factor: Double {
        switch self {
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        case .largest: 1.5
        }
    }

    /// `points` at this scale, to the nearest half point so the text stays crisp.
    public func scaled(_ points: Double) -> Double { (points * factor * 2).rounded() / 2 }

    /// The size chosen for this Mac, usual when there is none (or one this version doesn't know).
    public static func stored(in defaults: UserDefaults = .standard) -> TextScale {
        defaults.string(forKey: key).flatMap(TextScale.init(rawValue:)) ?? .standard
    }

    /// Remembers this size; the usual size is the absence of a choice.
    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(self == .standard ? nil : rawValue, forKey: Self.key)
    }

    /// One step larger or smaller, stopping at the ends.
    public var larger: TextScale { Self.allCases[min(Self.allCases.count - 1, Self.allCases.firstIndex(of: self)! + 1)] }
    public var smaller: TextScale { Self.allCases[max(0, Self.allCases.firstIndex(of: self)! - 1)] }
}
