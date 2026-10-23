import AVFoundation
import Foundation

/// A voice the system offers, reduced to what choosing one needs.
public struct VoiceChoice: Equatable, Sendable {
    public var identifier: String
    public var name: String
    /// A language tag such as "es-ES" or "ja-JP".
    public var language: String
    /// Higher is better: 1 standard, 2 enhanced, 3 premium.
    public var quality: Int

    public init(identifier: String, name: String, language: String, quality: Int) {
        self.identifier = identifier; self.name = name; self.language = language; self.quality = quality
    }
}

public enum VoiceSelection {
    /// The best voice for a language code such as "es" or "ja": the highest quality installed, whatever the region.
    /// At equal quality the older Eloquence voices (Eddy, Flo, Grandma...) rank below the standard ones such as
    /// Mónica or Kyoko, which sound more natural; after that the lowest identifier, so the answer never changes.
    public static func best(in voices: [VoiceChoice], forLanguage code: String) -> VoiceChoice? {
        let code = code.lowercased()
        return voices
            .filter { voice in
                let tag = voice.language.lowercased()
                return tag == code || tag.hasPrefix(code + "-") || tag.hasPrefix(code + "_")
            }
            .min { lhs, rhs in
                let l = (lhs.quality, isEloquence(lhs) ? 0 : 1), r = (rhs.quality, isEloquence(rhs) ? 0 : 1)
                return l != r ? l > r : lhs.identifier < rhs.identifier
            }
    }
}

private func isEloquence(_ voice: VoiceChoice) -> Bool { voice.identifier.lowercased().contains("eloquence") }

/// Says a word aloud with the best voice installed for its language. Uses the system's speech synthesizer, so it
/// works offline with no download; installing an Enhanced or Premium voice (System Settings > Accessibility >
/// Spoken Content) makes it sound better. The language comes from the profile's `whisperCode`.
@MainActor
public final class WordSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// The installed voices, without novelty voices (which sing, whisper and joke).
    nonisolated static func installedChoices() -> [VoiceChoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .map { VoiceChoice(identifier: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue) }
    }

    /// False when no voice for the language is installed; the caller should disable its button.
    public func isAvailable(languageCode: String) -> Bool {
        VoiceSelection.best(in: Self.installedChoices(), forLanguage: languageCode) != nil
    }

    /// Speaks `text`, replacing anything still being said. Does nothing if no voice for the language is installed,
    /// because the default voice would read it in the wrong language.
    public func speak(_ text: String, languageCode: String) {
        guard let choice = VoiceSelection.best(in: Self.installedChoices(), forLanguage: languageCode),
              let voice = AVSpeechSynthesisVoice(identifier: choice.identifier) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9   // a little slower: this is for learning
        synthesizer.speak(utterance)
    }

    public func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
