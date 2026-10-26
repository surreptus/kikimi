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

    private var speaker: WordSpeaker { .shared }
    /// Looked up once per language, not on every redraw (it lists every installed voice).
    @State private var available = true

    var body: some View {
        Group {
            if let shortcut { button(available).keyboardShortcut(shortcut, modifiers: []) } else { button(available) }
        }
        .task(id: languageCode) { available = speaker.isAvailable(languageCode: languageCode) }
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
            // The same icon size and frame as the ⋯ menu beside it in the word panel, so the two match.
            Button(action: action) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 14, weight: .medium)).frame(width: 22, height: 18)
            }
            .buttonStyle(.pill(.secondary, compact: true))
            .accessibilityLabel("Say word")
            .disabled(!available).help(help)
        }
    }
}
