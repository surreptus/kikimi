import Foundation

/// Translates a video's lines on request and keeps the results, so each line is translated once.
public actor TranslationService {
    private let database: LangDatabase
    private let translator: any LineTranslator
    nonisolated public let target: String
    private let batchSize: Int

    public init(database: LangDatabase, translator: any LineTranslator, target: String, batchSize: Int = 24) {
        self.database = database
        self.translator = translator
        self.target = target
        self.batchSize = batchSize
    }

    public func availability() async -> TranslationAvailability { await translator.availability() }

    /// The translations already kept for a video.
    public func stored(videoID: Int64) async throws -> [Int64: String] {
        try await database.translations(videoID: videoID, target: target)
    }

    /// The translation of each of `lines` that has one, by line id. A line already translated is read from storage and
    /// not asked for again; the rest are translated now and kept.
    public func translate(_ lines: [Subtitle]) async throws -> [Int64: String] {
        var seen = Set<Int64>()
        // Asked for twice, translated once; and a line with no words in it (a lone "♪") has nothing to translate.
        let wanted = lines.filter { $0.id != nil && TranslationText.hasWords($0.text) && seen.insert($0.id!).inserted }
        var made = try await database.translations(ids: wanted.map { $0.id! }, target: target)
        let pending = wanted.filter { made[$0.id!] == nil }
        var index = 0
        while index < pending.count {
            let batch = Array(pending[index..<min(index + batchSize, pending.count)])
            index += batchSize
            let translated = try await translator.translate(batch.map(\.text))
            var kept: [Int64: String] = [:]
            for (line, text) in zip(batch, translated) {
                if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { kept[line.id!] = text }
            }
            try await database.saveTranslations(kept, target: target)
            made.merge(kept) { _, new in new }
        }
        return made
    }
}
