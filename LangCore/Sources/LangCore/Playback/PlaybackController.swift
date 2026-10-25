import AVFoundation
import Observation

/// Drives an AVPlayer and keeps the active subtitle line in sync. The app wraps `player` in a video view.
@MainActor @Observable
public final class PlaybackController {
    public let player: AVPlayer
    public let lines: [Subtitle]
    public private(set) var activeIndex: Int?
    public private(set) var currentTime: Double = 0
    public private(set) var isPlaying = false

    @ObservationIgnored private let timeline: SubtitleTimeline
    @ObservationIgnored private var observer: Any?

    public init(url: URL, lines: [Subtitle]) {
        player = AVPlayer(url: url)
        timeline = SubtitleTimeline(lines)
        self.lines = timeline.lines
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    /// Call when the player screen goes away.
    public func stop() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        isPlaying = false
    }

    public func play() { player.play(); isPlaying = true }
    public func pause() { player.pause(); isPlaying = false }
    public func togglePlayback() { isPlaying ? pause() : play() }

    public func seek(to seconds: Double, play shouldPlay: Bool = false) async {
        let target = max(0, seconds)
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        activeIndex = timeline.index(at: target + 0.001)
        if shouldPlay { play() }
    }

    public func seek(toLine index: Int, play shouldPlay: Bool = true) async {
        guard lines.indices.contains(index) else { return }
        await seek(to: lines[index].startTime, play: shouldPlay)
        activeIndex = index
    }

    public func nextLine() async {
        await seek(toLine: min((activeIndex ?? -1) + 1, lines.count - 1))
    }

    public func previousLine() async {
        await seek(toLine: max((activeIndex ?? 1) - 1, 0))
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        isPlaying = player.rate != 0
        activeIndex = timeline.index(at: seconds)
    }
}
