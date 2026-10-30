import Foundation
import GRDB

extension LangDatabase {
    /// Replaces the text of a subtitle line, and the words found in it, because Whisper got it wrong; `start` and `end`
    /// (seconds) move its timing when given. Words you have started learning or marked are kept; words still "new" that
    /// now appear nowhere are removed, as when a video is deleted. Returns the line as saved.
    @discardableResult
    public func editSubtitle(
        id: Int64, text: String, start: Double? = nil, end: Double? = nil, profile: any LanguageProfile
    ) async throws -> Subtitle {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LangError.emptyLine }
        let tokens = profile.contentWords(in: trimmed)
        return try await writer.write { db in
            guard var subtitle = try Subtitle.fetchOne(db, key: id) else { throw LangError.notFound }
            if start != nil || end != nil {
                let newStart = start ?? subtitle.startTime, newEnd = end ?? subtitle.endTime
                let duration = try Video.fetchOne(db, key: subtitle.videoId)?.duration ?? .infinity
                guard newStart >= 0, newEnd > newStart + 0.1, newEnd <= duration + 0.5 else { throw LangError.badTiming }
                subtitle.startTime = newStart
                subtitle.endTime = newEnd
            }
            subtitle.text = trimmed
            try subtitle.update(db)
            try db.execute(sql: "DELETE FROM occurrences WHERE subtitle_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM translations WHERE subtitle_id = ?", arguments: [id])   // it was of the old text
            var cache: [WordKey: Int64] = [:]
            for token in tokens {
                let wordID = try Self.wordID(for: token, language: profile.code, cache: &cache, in: db)
                var occurrence = Occurrence(wordId: wordID, subtitleId: id, surface: token.surface)
                try occurrence.insert(db, onConflict: .ignore)
            }
            try db.execute(sql: """
                DELETE FROM words
                WHERE language = ? AND status = 'new'
                  AND NOT EXISTS (SELECT 1 FROM occurrences WHERE occurrences.word_id = words.id)
                """, arguments: [profile.code])
            return subtitle
        }
    }
}
