import Foundation

/// How the library's copy of a video is made.
public enum VideoQuality: String, CaseIterable, Sendable {
    /// Re-encoded small (see `VideoPlan`): a fraction of the size, good enough to follow along and study from.
    case smallest
    /// Your file exactly as it is, no re-encoding: the best picture and sound, and the same size as the original.
    case original
}

/// The chosen quality, kept in the app's settings.
public struct VideoQualityPreference: @unchecked Sendable {
    public static let key = "videoQuality"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var quality: VideoQuality {
        get { defaults.string(forKey: Self.key).flatMap(VideoQuality.init(rawValue:)) ?? .smallest }
        nonmutating set { defaults.set(newValue == .smallest ? nil : newValue.rawValue, forKey: Self.key) }
    }
}
