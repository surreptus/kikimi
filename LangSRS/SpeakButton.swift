import LangCore
import SwiftUI

/// Says a word with the system voice for its language. Disabled, with the reason in its help text, when no voice
/// for that language is installed.
struct SpeakButton: View {
    let text: String
    /// The profile's `whisperCode`, such as "es" or "ja".
    let languageCode: String
    var showsTitle = false
    var shortcut: KeyEquivalent?

    @State private var speaker = WordSpeaker()

    var body: some View {
        let available = speaker.isAvailable(languageCode: languageCode)
        Group {
            if let shortcut { button(available).keyboardShortcut(shortcut, modifiers: []) } else { button(available) }
        }
        .onDisappear { speaker.stop() }
    }

    @ViewBuilder
    private func button(_ available: Bool) -> some View {
        let help = available
            ? "Say the word\(shortcut.map { " (\($0.character.uppercased()))" } ?? "")"
            : "No voice for this language is installed. Add one in System Settings > Accessibility > Spoken Content."
        let action = { speaker.speak(text, languageCode: languageCode) }
        if showsTitle {
            Button("Say word", systemImage: "speaker.wave.2.fill", action: action)
                .labelStyle(.titleAndIcon).buttonStyle(.pill(.secondary, compact: true))
                .disabled(!available).help(help)
        } else {
            Button("Say word", systemImage: "speaker.wave.2.fill", action: action)
                .labelStyle(.iconOnly).buttonStyle(.pill(.secondary, compact: true))
                .disabled(!available).help(help)
        }
    }
}
