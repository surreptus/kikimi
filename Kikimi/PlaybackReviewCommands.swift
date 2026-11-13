import LangCore
import SwiftUI

// The Playback and Review menus. The single-key shortcuts live here, not on buttons, so the menu bar lists every one.
// A view offers its actions with `focusedSceneValue`, so an item is enabled only while the action can work, and only
// while that screen is up. Each menu item owns its key: a button shows the key in its help text but does not bind it.
//
// Text fields: a menu item with a bare letter must never take a key from a text field. Two rules keep that true.
// 1. The views offer no bare-key action while a text field or an edit sheet has focus (`reviewTyping`, `editingLine`).
// 2. These menus disable every bare-key item then. AppKit also skips a bare-key menu item while a field editor is active.

/// What the player offers to the Playback menu.
struct PlaybackActions {
    var available: Set<PlaybackCommand>
    var isPlaying: Bool
    var isLooping: Bool
    var pausesAfterLine: Bool
    var subtitlesHidden: Bool
    var perform: (PlaybackCommand) -> Void
}

extension FocusedValues {
    @Entry var playbackActions: PlaybackActions?
    /// The review keys that need a card's own state, offered by the card's buttons that have them.
    @Entry var reviewShortcutActions: [ReviewShortcut: () -> Void]?
    @Entry var reviewShowAnswer: (() -> Void)?
    @Entry var reviewMissed: (() -> Void)?
    @Entry var reviewGot: (() -> Void)?
    @Entry var reviewPlaySentence: (() -> Void)?
    @Entry var reviewRecord: (() -> Void)?
    @Entry var reviewHearYourself: (() -> Void)?
    /// True while a text field or an edit sheet has the keyboard.
    @Entry var reviewTyping: Bool?
}

extension ReviewShortcut {
    /// The menu item's name: the same words as the hint under the card.
    var title: String {
        switch self {
        case .check: String(localized: "Check")
        case .playAgain: String(localized: "Play again")
        case .sayWord: String(localized: "Say word")
        case .wordPage: String(localized: "Word page")
        case .furigana: String(localized: "Furigana")
        case .editSentence: String(localized: "Edit sentence")
        case .translation: String(localized: "Translation")
        }
    }

    /// Return belongs to the text field's own submit, so Check has no key in the menu. The rest keep their key.
    fileprivate var menuShortcut: KeyboardShortcut? {
        switch self {
        case .check: nil
        case .playAgain: KeyboardShortcut("r", modifiers: .command)
        default: letter.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) }
        }
    }
}

struct PlaybackReviewCommands: Commands {
    @FocusedValue(\.playbackActions) private var playback
    @FocusedValue(\.reviewShortcutActions) private var reviewShortcuts
    @FocusedValue(\.reviewShowAnswer) private var showAnswer
    @FocusedValue(\.reviewMissed) private var missed
    @FocusedValue(\.reviewGot) private var got
    @FocusedValue(\.reviewPlaySentence) private var playSentence
    @FocusedValue(\.reviewRecord) private var record
    @FocusedValue(\.reviewHearYourself) private var hearYourself
    @FocusedValue(\.reviewTyping) private var typing

    var body: some Commands {
        CommandMenu("Playback") {
            playbackItem(playback?.isPlaying == true ? String(localized: "Pause") : String(localized: "Play"), .playPause, .space)
            playbackItem(String(localized: "Previous Line"), .previousLine, .leftArrow, .command)
            playbackItem(String(localized: "Next Line"), .nextLine, .rightArrow, .command)
            Divider()
            playbackToggle(String(localized: "Repeat Line"), .loopLine, "r", on: playback?.isLooping)
            playbackToggle(String(localized: "Pause After Each Line"), .pauseAfterLine, "p", on: playback?.pausesAfterLine)
            playbackToggle(String(localized: "Hide Subtitles"), .hideSubtitles, "h", on: playback?.subtitlesHidden)
            Divider()
            playbackItem(String(localized: "Pick Words"), .focusTranscript, .downArrow, .command)
            Divider()
            // Learn and Restore share a key: only one of them can work for a word.
            if playback?.available.contains(.restoreWord) == true {
                playbackItem(String(localized: "Restore Word"), .restoreWord, "l")
            } else {
                playbackItem(String(localized: "Learn Word"), .learnWord, "l")
            }
            playbackItem(String(localized: "Mark Word as Known"), .knownWord, "k")
            playbackItem(String(localized: "Ignore Word"), .ignoreWord, "x")
        }

        CommandMenu("Review") {
            cardItem("Show Answer", showAnswer, .space)
            cardItem("Missed It", missed, .leftArrow)
            cardItem("Got It", got, .rightArrow)
            Divider()
            cardItem("Play Sentence", playSentence, "r")
            cardItem("Record Yourself", record, "m")
            cardItem("Hear Yourself", hearYourself, "y")
            Divider()
            let enabled = ReviewShortcut.menuKeys(offered: Array((reviewShortcuts ?? [:]).keys), textFieldFocused: typing ?? false)
            ForEach(ReviewShortcut.allCases, id: \.self) { shortcut in
                Button(shortcut.title) { reviewShortcuts?[shortcut]?() }
                    .keyboardShortcut(shortcut.menuShortcut)
                    .disabled(!enabled.contains(shortcut))
            }
        }
    }

    private func playbackItem(_ title: String, _ command: PlaybackCommand, _ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> some View {
        Button(title) { playback?.perform(command) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(playback?.available.contains(command) != true)
    }

    private func playbackToggle(_ title: String, _ command: PlaybackCommand, _ key: KeyEquivalent, on: Bool?) -> some View {
        Toggle(title, isOn: Binding(get: { on ?? false }, set: { _ in playback?.perform(command) }))
            .keyboardShortcut(key, modifiers: [])
            .disabled(playback?.available.contains(command) != true)
    }

    /// A card key with its own button. Off while a text field has the keyboard, since its key is a bare letter, space or arrow.
    private func cardItem(_ title: LocalizedStringKey, _ action: (() -> Void)?, _ key: KeyEquivalent) -> some View {
        Button(title) { action?() }
            .keyboardShortcut(key, modifiers: [])
            .disabled(action == nil || typing == true)
    }
}
