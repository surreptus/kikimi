import AVFoundation
import Observation

/// Drives an AVPlayer and keeps the active subtitle line in sync. The app wraps `player` in a video view.
@MainActor @Observable
public final class PlaybackController {
    public let player: AVPlayer
    public private(set) var lines: [Subtitle]
    public private(set) var activeIndex: Int?
    public private(set) var currentTime: Double = 0
    public private(set) var isPlaying = false

    /// Pause when the line being played ends, so you can think about it, look a word up, or hear it again.
    public var pausesAfterLines = false {
        didSet { arm(activeIndex) }
    }

    @ObservationIgnored private let timeline: SubtitleTimeline
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var lineEnd: Any?

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
        disarm()
        isPlaying = false
    }

    /// Changes one line's text (after it is edited). Timing is untouched, so playback carries on undisturbed.
    public func replaceText(at index: Int, with text: String) {
        guard lines.indices.contains(index) else { return }
        lines[index].text = text
    }

    public func play() { player.play(); isPlaying = true }
    public func pause() { player.pause(); isPlaying = false }
    public func togglePlayback() { isPlaying ? pause() : play() }

    public func seek(to seconds: Double, play shouldPlay: Bool = false) async {
        let target = max(0, seconds)
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        activeIndex = timeline.index(at: target + 0.001)
        arm(activeIndex)
        if shouldPlay { play() }
    }

    public func seek(toLine index: Int, play shouldPlay: Bool = true) async {
        guard lines.indices.contains(index) else { return }
        await seek(to: lines[index].startTime, play: shouldPlay)
        activeIndex = index
        arm(index)
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
        let previous = activeIndex
        activeIndex = timeline.index(at: seconds)
        if activeIndex != previous { arm(activeIndex) }
    }

    // MARK: Pausing after a line

    /// Watches for the end of line `index`, so the pause lands on it rather than up to a tick later.
    private func arm(_ index: Int?) {
        disarm()
        guard pausesAfterLines, let index, lines.indices.contains(index) else { return }
        let end = lines[index].endTime
        guard end > currentTime + 0.02 else { return }
        lineEnd = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: end, preferredTimescale: 600))], queue: .main
        ) { [weak self] in MainActor.assumeIsolated { self?.pauseAtLineEnd() } }
    }

    private func disarm() {
        if let lineEnd { player.removeTimeObserver(lineEnd) }
        lineEnd = nil
    }

    private func pauseAtLineEnd() {
        disarm()
        pause()
    }
}
