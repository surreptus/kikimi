import Foundation

public struct Acknowledgement: Sendable, Identifiable {
    public let title: String
    public let text: String
    public var id: String { title }
}

/// Licence and attribution texts for bundled software and data.
public enum Acknowledgements {
    private static let titles = [
        "JMdict-EDRDG": "JMdict dictionary data",
        "Wiktionary-kaikki": "Spanish dictionary data (Wiktionary)",
        "IPADIC-COPYING": "IPADIC dictionary (NAIST, ICOT)",
        "MeCab-BSD": "MeCab morphological analyzer",
        "OpenAI-Whisper": "Whisper speech recognition",
        "WhisperKit-MIT": "WhisperKit",
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
