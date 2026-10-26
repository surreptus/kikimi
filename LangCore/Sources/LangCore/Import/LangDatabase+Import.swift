import Foundation
import GRDB

extension LangDatabase {
    /// The id of the word a token is, adding the word if it is new. `cache` spares repeat lookups within one write.
    static func wordID(for token: Token, language: String, cache: inout [WordKey: Int64], in db: Database) throws -> Int64 {
        let key = WordKey(lemma: token.lemma, pos: token.pos)
        if let cached = cache[key] { return cached }
        let id: Int64
        if let existing = try Word
            .filter(Column("language") == language && Column("lemma") == token.lemma && Column("pos") == token.pos.rawValue)
            .fetchOne(db) {
            id = existing.id!
        } else {
            var word = Word(language: language, lemma: token.lemma, pos: token.pos)
            try word.insert(db)
            id = word.id!
        }
        cache[key] = id
        return id
    }

    public func videoID(forContentHash hash: String) async throws -> Int64? {
        try await writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM videos WHERE content_hash = ?", arguments: [hash])
        }
    }

    /// Writes the video, its subtitles, new words and occurrences in one transaction.
    public func saveImport(
        video: Video, subtitles: [(segment: TranscriptSegment, tokens: [Token])]
    ) async throws -> Video {
        try await writer.write { db in
            var video = video
            try video.insert(db)
            var wordIDs: [WordKey: Int64] = [:]

            for (index, item) in subtitles.enumerated() {
                var subtitle = Subtitle(
                    videoId: video.id!, idx: index,
                    startTime: item.segment.start, endTime: item.segment.end, text: item.segment.text)
                try subtitle.insert(db)

                for token in item.tokens {
                    let wordID = try Self.wordID(for: token, language: video.language, cache: &wordIDs, in: db)
                    var occurrence = Occurrence(wordId: wordID, subtitleId: subtitle.id!, surface: token.surface)
                    try occurrence.insert(db, onConflict: .ignore)
                }
            }
            return video
        }
    }
}
