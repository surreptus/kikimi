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

    /// The line being repeated, until you turn looping off or go somewhere else.
    public private(set) var loopingIndex: Int?
    /// How fast a looped line plays: 1 is normal. Slower makes a hard line easier to catch.
    public var loopSpeed: Float = 1 {
        didSet { if loopingIndex != nil { applyLoopRate() } }
    }

    /// Told how many seconds you have watched, every so often and when the screen closes. For the listening tally.
    public var onListened: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored private var listenedPending: TimeInterval = 0
    @ObservationIgnored private var lastTickAt: Date?

    @ObservationIgnored private var timeline: SubtitleTimeline
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var boundary: Any?
    /// Set while a range is being previewed: playback pauses there.
    @ObservationIgnored private var rangeEnd: Double?
    /// A little before a line, so its first word isn't clipped when it starts over.
    private static let loopLeadIn = 0.15

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
        flushListening()
        lastTickAt = nil
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        disarm()
        loopingIndex = nil
        rangeEnd = nil
        player.defaultRate = 1
        isPlaying = false
    }

    /// Puts an edited line in place (its text, and its timing if that changed), and tells the timeline.
    public func replaceLine(at index: Int, with line: Subtitle) {
        guard lines.indices.contains(index) else { return }
        var updated = lines
        updated[index] = line
        timeline = SubtitleTimeline(updated)
        lines = timeline.lines
        if loopingIndex != nil { loopingIndex = lines.firstIndex { $0.id == line.id } }
        activeIndex = timeline.index(at: currentTime)
        arm(activeIndex)
    }

    public func play() { player.play(); isPlaying = true }
    public func pause() { player.pause(); isPlaying = false }
    public func togglePlayback() { isPlaying ? pause() : play() }

    // MARK: Seeking

    /// Where you chose to go: any loop or previewed range ends.
    public func seek(to seconds: Double, play shouldPlay: Bool = false) async {
        stopLooping()
        rangeEnd = nil
        await move(to: seconds, play: shouldPlay)
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

    private func move(to seconds: Double, play shouldPlay: Bool) async {
        let target = max(0, seconds)
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        activeIndex = timeline.index(at: target + 0.001)
        arm(activeIndex)
        if shouldPlay { play() }
    }

    /// Reports the time watched so far (under a second isn't worth reporting) and starts counting again.
    public func flushListening() {
        guard listenedPending >= 1 else { return }
        let seconds = listenedPending
        listenedPending = 0
        onListened?(seconds)
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        isPlaying = player.rate != 0
        // Real time spent playing. A gap (the Mac slept, the app was busy) counts as at most a second.
        let now = Date()
        if isPlaying, let last = lastTickAt { listenedPending += min(now.timeIntervalSince(last), 1) }
        lastTickAt = isPlaying ? now : nil
        if listenedPending >= 15 { flushListening() }
        let previous = activeIndex
        activeIndex = timeline.index(at: seconds)
        if activeIndex != previous { arm(activeIndex) }
    }

    // MARK: Looping

    /// Starts repeating the line being played (or the nearest one), or stops.
    public func toggleLoop() async {
        if loopingIndex != nil { stopLooping(); return }
        guard let index = activeIndex ?? lines.lastIndex(where: { $0.startTime <= currentTime }) ?? lines.indices.first
        else { return }
        rangeEnd = nil
        loopingIndex = index
        applyLoopRate()
        await startLoopPass()
    }

    public func stopLooping() {
        guard loopingIndex != nil else { return }
        loopingIndex = nil
        player.defaultRate = 1
        if isPlaying { player.rate = 1 }
        arm(activeIndex)
    }

    private func applyLoopRate() {
        player.defaultRate = loopSpeed
        if isPlaying { player.rate = loopSpeed }
    }

    private func startLoopPass() async {
        guard let index = loopingIndex, lines.indices.contains(index) else { return }
        await move(to: lines[index].startTime - Self.loopLeadIn, play: true)
    }

    // MARK: Previewing a range

    /// Plays `start...end` once and pauses, for checking a line's timing while it is being edited.
    public func playRange(from start: Double, to end: Double) async {
        stopLooping()
        rangeEnd = end
        await move(to: start, play: true)
    }

    // MARK: Boundary: where the current line, loop or range ends

    /// Watches for the moment playback should stop or turn back, so it lands on it rather than up to a tick later.
    private func arm(_ index: Int?) {
        disarm()
        if let end = rangeEnd {
            watch(end) { $0.finishRange() }
        } else if let loop = loopingIndex, lines.indices.contains(loop) {
            watch(lines[loop].endTime) { controller in Task { await controller.startLoopPass() } }
        } else if pausesAfterLines, let index, lines.indices.contains(index) {
            watch(lines[index].endTime) { $0.pauseAtBoundary() }
        }
    }

    private func watch(_ time: Double, then action: @escaping @MainActor (PlaybackController) -> Void) {
        guard time > currentTime + 0.02 else { return }
        boundary = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: time, preferredTimescale: 600))], queue: .main
        ) { [weak self] in MainActor.assumeIsolated { if let self { action(self) } } }
    }

    private func disarm() {
        if let boundary { player.removeTimeObserver(boundary) }
        boundary = nil
    }

    private func pauseAtBoundary() {
        disarm()
        pause()
    }

    private func finishRange() {
        rangeEnd = nil
        pauseAtBoundary()
    }
}
