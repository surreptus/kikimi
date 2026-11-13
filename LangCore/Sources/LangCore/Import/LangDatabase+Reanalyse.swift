import Foundation
import GRDB

/// What "Find words again" did, for the summary the learner reads.
public struct ReanalysisReport: Equatable, Sendable {
    /// Videos whose lines were read again.
    public var videosLooked = 0
    /// Videos left alone because no profile exists for their language.
    public var videosSkipped = 0
    /// Words that did not exist before.
    public var wordsAdded = 0
    /// Words that appeared in some video before, and now appear in none. They are kept, with their progress.
    public var wordsInNoVideo = 0

    public init(videosLooked: Int = 0, videosSkipped: Int = 0, wordsAdded: Int = 0, wordsInNoVideo: Int = 0) {
        self.videosLooked = videosLooked; self.videosSkipped = videosSkipped
        self.wordsAdded = wordsAdded; self.wordsInNoVideo = wordsInNoVideo
    }
}

extension LangDatabase {
    /// Reads the stored lines of every video again with the current tokenizer, so fixes made since the import reach
    /// videos imported before them. It uses the lines as saved (edits included) and needs no file, model or network.
    ///
    /// It changes only `occurrences` and adds `words`. A word is never removed or changed, so status, stage, next
    /// review and activity stay, even for a word the tokenizer no longer finds. A word found for the first time is
    /// `new`. A changed lemma gives a second word; the old one is not merged.
    ///
    /// Each video is one transaction, so a failure leaves that video as it was. Videos done before it are complete,
    /// and a second run carries on from there. A run with nothing to change writes nothing.
    public func reanalyseWords(
        profileFor: @Sendable (String) -> (any LanguageProfile)? = { LanguageProfiles.profile(for: $0) },
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> ReanalysisReport {
        let videos = try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, language FROM videos ORDER BY id").map { ($0["id"] as Int64, $0["language"] as String) }
        }
        let unseenBefore = try await wordsInNoVideoCount()
        var report = ReanalysisReport()
        progress(0, videos.count)
        for (index, (videoID, language)) in videos.enumerated() {
            try Task.checkCancellation()
            if let profile = profileFor(language) {
                report.wordsAdded += try await writer.write { db in
                    try Self.reanalyse(videoID: videoID, language: language, profile: profile, in: db)
                }
                report.videosLooked += 1
            } else {
                report.videosSkipped += 1
            }
            progress(index + 1, videos.count)
        }
        // Words are only added with an occurrence, so any rise in this count is a word that lost its last one.
        report.wordsInNoVideo = max(0, try await wordsInNoVideoCount() - unseenBefore)
        return report
    }

    private func wordsInNoVideoCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words WHERE NOT EXISTS (SELECT 1 FROM occurrences WHERE word_id = words.id)") ?? 0
        }
    }

    private struct OccurrenceKey: Hashable { let word: Int64, subtitle: Int64 }

    /// Brings one video's occurrences in line with its lines. Rows that are already right are not touched.
    /// Returns how many words were added.
    private static func reanalyse(videoID: Int64, language: String, profile: any LanguageProfile, in db: Database) throws -> Int {
        let wordsBefore = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words WHERE language = ?", arguments: [language]) ?? 0

        var existing: [OccurrenceKey: (id: Int64, surface: String)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT occurrences.id AS id, word_id, subtitle_id, surface FROM occurrences
            JOIN subtitles ON subtitles.id = occurrences.subtitle_id WHERE subtitles.video_id = ?
            """, arguments: [videoID]) {
            existing[OccurrenceKey(word: row["word_id"], subtitle: row["subtitle_id"])] = (row["id"], row["surface"])
        }

        var wanted: [OccurrenceKey: String] = [:]
        var wordIDs: [WordKey: Int64] = [:]
        for line in try Row.fetchAll(db, sql: "SELECT id, text FROM subtitles WHERE video_id = ? ORDER BY idx", arguments: [videoID]) {
            let subtitleID: Int64 = line["id"]
            for token in profile.contentWords(in: line["text"]) {
                let wordID = try Self.wordID(for: token, language: language, cache: &wordIDs, in: db)
                let key = OccurrenceKey(word: wordID, subtitle: subtitleID)
                if wanted[key] == nil { wanted[key] = token.surface }   // the first one wins, as on import
            }
        }

        for (key, old) in existing where wanted[key] != old.surface {
            try db.execute(sql: "DELETE FROM occurrences WHERE id = ?", arguments: [old.id])
        }
        for (key, surface) in wanted where existing[key]?.surface != surface {
            var occurrence = Occurrence(wordId: key.word, subtitleId: key.subtitle, surface: surface)
            try occurrence.insert(db)
        }
        let wordsAfter = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words WHERE language = ?", arguments: [language]) ?? 0
        return wordsAfter - wordsBefore
    }
}

extension LangEnvironment {
    /// "Find words again" for the views: every video, with the profile of its language.
    public func findWordsAgain(progress: @Sendable @escaping (_ done: Int, _ total: Int) -> Void) async throws -> ReanalysisReport {
        try await database.reanalyseWords(progress: progress)
    }
}
