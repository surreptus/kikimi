import AVFoundation
import Foundation
import Observation

/// When review cards speak their example sentence.
public enum SentenceAudioMode: String, CaseIterable, Sendable {
    case off
    case onReveal      // when the answer is shown
    case onCardShown   // listening first: audio plays before the text is revealed

    public var title: String {
        switch self {
        case .off: "Off"
        case .onReveal: "When the answer is shown"
        case .onCardShown: "When the card appears"
        }
    }
}

public struct ReviewAudioPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func mode(for profile: any LanguageProfile) -> SentenceAudioMode {
        defaults.string(forKey: key(profile)).flatMap(SentenceAudioMode.init) ?? .onReveal
    }

    public func setMode(_ mode: SentenceAudioMode, for profile: any LanguageProfile) {
        defaults.set(mode.rawValue, forKey: key(profile))
    }

    private func key(_ profile: any LanguageProfile) -> String { "sentenceAudio.\(profile.code)" }
}

/// Plays one subtitle line's audio from the library, then stops by itself.
@MainActor @Observable
public final class SentenceAudioPlayer {
    public private(set) var isPlaying = false
    public var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    @ObservationIgnored private let libraryRoot: URL
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var boundary: Any?
    @ObservationIgnored private var endToken: NSObjectProtocol?
    @ObservationIgnored private var generation = 0

    public init(libraryRoot: URL) { self.libraryRoot = libraryRoot }

    /// Starts the line (replacing anything already playing). Returns false if its audio file is missing.
    @discardableResult
    public func play(_ line: ExampleLine, padding: Double = ClipExporter.defaultPadding) async -> Bool {
        stop()
        generation += 1
        let mine = generation
        let url = libraryRoot.appending(path: line.mediaPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let start = max(0, line.startTime - padding)
        let end = line.endTime + padding
        await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard mine == generation else { return false }   // a newer play() or stop() won while seeking

        boundary = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: end, preferredTimescale: 600))], queue: .main
        ) { [weak self] in MainActor.assumeIsolated { self?.stop() } }
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
        player.play()
        isPlaying = true
        return true
    }

    public func stop() {
        generation += 1
        player.pause()
        if let boundary { player.removeTimeObserver(boundary) }
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        boundary = nil
        endToken = nil
        isPlaying = false
    }
}
