import Foundation

/// The commands of the Playback menu. The menu lists every one, and `available` says which can work now, so a menu item is
/// enabled only when its action does something.
public enum PlaybackCommand: CaseIterable, Sendable, Equatable {
    case playPause, previousLine, nextLine, pauseAfterLine, hideSubtitles, loopLine, focusTranscript
    case learnWord, restoreWord, knownWord, ignoreWord

    /// What can be done now. Nothing while the video is not ready or a line is being edited (a sheet: its text field must keep every key).
    /// The word commands need a word in the meaning bar. `status` is that word's status, or nil when it has none yet.
    public static func available(videoReady: Bool, editingLine: Bool, hasWord: Bool, status: WordStatus?) -> Set<PlaybackCommand> {
        guard videoReady, !editingLine else { return [] }
        var result: Set<PlaybackCommand> = [.playPause, .previousLine, .nextLine, .pauseAfterLine, .hideSubtitles, .loopLine, .focusTranscript]
        guard hasWord else { return result }
        if status == .ignored { result.insert(.restoreWord) }
        if status != .learning, status != .finished, status != .ignored { result.insert(.learnWord) }
        if status != .known, status != .ignored { result.insert(.knownWord) }
        if status == .new { result.insert(.ignoreWord) }
        return result
    }
}
