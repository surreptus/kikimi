import Foundation

public struct Acknowledgement: Sendable, Identifiable {
    public let title: String
    public let text: String
    public var id: String { title }
}

/// Licence and attribution texts for bundled software and data.
public enum Acknowledgements {
    private static let titles = [
        "Kikimi-MIT": "Kikimi (this app)",
        "JMdict-EDRDG": "JMdict dictionary data",
        "KANJIDIC-EDRDG": "KANJIDIC2 kanji data",
        "Wiktionary-kaikki": "Spanish, French and German dictionary data (Wiktionary)",
        "IPADIC-COPYING": "IPADIC dictionary (NAIST, ICOT)",
        "MeCab-BSD": "MeCab morphological analyzer",
        "OpenAI-Whisper": "Whisper speech recognition",
        "WhisperKit-MIT": "WhisperKit",
        "swift-transformers-Apache-2.0": "swift-transformers (Hugging Face), inside WhisperKit",
        "GRDB-MIT": "GRDB.swift",
    ]

    public static func all() -> [Acknowledgement] {
        guard let folder = Bundle.module.url(forResource: "Licenses", withExtension: nil) else { return [] }
        return titles.keys.sorted().compactMap { name in
            // Lenient decoding: IPADIC's original COPYING ends with stray non-UTF-8 bytes.
            guard let data = try? Data(contentsOf: folder.appending(path: "\(name).txt")) else { return nil }
            return Acknowledgement(title: titles[name]!, text: String(decoding: data, as: UTF8.self))
        }
    }
}
