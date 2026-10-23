import Foundation
import GRDB

extension LangDatabase {
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
            struct Key: Hashable { let lemma: String; let pos: PartOfSpeech }

            var video = video
            try video.insert(db)
            var wordIDs: [Key: Int64] = [:]

            for (index, item) in subtitles.enumerated() {
                var subtitle = Subtitle(
                    videoId: video.id!, idx: index,
                    startTime: item.segment.start, endTime: item.segment.end, text: item.segment.text)
                try subtitle.insert(db)

                for token in item.tokens {
                    let key = Key(lemma: token.lemma, pos: token.pos)
                    let wordID: Int64
                    if let cached = wordIDs[key] {
                        wordID = cached
                    } else if let existing = try Word
                        .filter(Column("language") == video.language && Column("lemma") == token.lemma
                                && Column("pos") == token.pos.rawValue)
                        .fetchOne(db) {
                        wordID = existing.id!
                    } else {
                        var word = Word(language: video.language, lemma: token.lemma, pos: token.pos)
                        try word.insert(db)
                        wordID = word.id!
                    }
                    wordIDs[key] = wordID
                    var occurrence = Occurrence(wordId: wordID, subtitleId: subtitle.id!, surface: token.surface)
                    try occurrence.insert(db, onConflict: .ignore)
                }
            }
            return video
        }
    }
}
