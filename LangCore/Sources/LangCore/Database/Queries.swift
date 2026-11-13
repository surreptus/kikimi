import Foundation
import GRDB

public struct LibraryEntry: Sendable, FetchableRecord, Identifiable {
    public let video: Video
    public let subtitleCount: Int
    public var id: Int64 { video.id! }

    public init(row: Row) throws {
        video = try Video(row: row)
        subtitleCount = row["subtitle_count"]
    }
}

public struct WordRow: Sendable, FetchableRecord, Identifiable {
    public let word: Word
    /// How many subtitle lines in your videos contain this word.
    public let occurrenceCount: Int
    public var id: Int64 { word.id! }

    public init(row: Row) throws {
        word = try Word(row: row)
        occurrenceCount = row["occurrence_count"]
    }

    public init(word: Word, occurrenceCount: Int = 0) {
        self.word = word
        self.occurrenceCount = occurrenceCount
    }
}

public struct ExampleLine: Sendable, FetchableRecord, Identifiable {
    public let id: Int64
    public let surface: String
    public let text: String
    public let startTime: Double
    public let endTime: Double
    public let videoID: Int64
    public let videoTitle: String
    /// Path under the library folder of the audio (or, for older imports, video) holding this line.
    public let mediaPath: String

    public init(row: Row) throws {
        id = row["subtitle_id"]
        surface = row["surface"]
        text = row["text"]
        startTime = row["start_time"]
        endTime = row["end_time"]
        videoID = row["video_id"]
        videoTitle = row["video_title"]
        mediaPath = row["media_path"]
    }

    public init(id: Int64, surface: String, text: String, startTime: Double, endTime: Double,
                videoID: Int64, videoTitle: String, mediaPath: String) {
        self.id = id; self.surface = surface; self.text = text; self.startTime = startTime; self.endTime = endTime
        self.videoID = videoID; self.videoTitle = videoTitle; self.mediaPath = mediaPath
    }

    /// This line with a corrected text or timing, for a screen that holds it after the transcript line was edited.
    public func edited(text: String? = nil, start: Double? = nil, end: Double? = nil) -> ExampleLine {
        ExampleLine(id: id, surface: surface, text: text ?? self.text, startTime: start ?? startTime, endTime: end ?? endTime,
                    videoID: videoID, videoTitle: videoTitle, mediaPath: mediaPath)
    }
}

extension LangDatabase {
    public func libraryVideos(language: String? = nil) async throws -> [LibraryEntry] {
        try await writer.read { db in
            try LibraryEntry.fetchAll(db, sql: """
                SELECT videos.*, (SELECT COUNT(*) FROM subtitles WHERE video_id = videos.id) AS subtitle_count
                FROM videos WHERE (? IS NULL OR language = ?)
                ORDER BY imported_at DESC, id DESC
                """, arguments: [language, language])
        }
    }

    /// How long after it is added a video that has not been played still offers its next steps in the list.
    public static let unwatchedWindow: TimeInterval = 14 * 24 * 3600

    /// The videos of `language` added within the window that have never been played, so the list can offer to mark the words
    /// you know or to learn the ones the video needs. Playing a video (even briefly) ends it.
    public func unwatchedVideoIDs(language: String, now: Date = Date()) async throws -> Set<Int64> {
        let since = now.addingTimeInterval(-Self.unwatchedWindow)
        return try await writer.read { db in
            Set(try Int64.fetchAll(db, sql: """
                SELECT id FROM videos WHERE language = ? AND imported_at > ?
                AND id NOT IN (SELECT subject FROM activity WHERE kind = 'listen')
                """, arguments: [language, since]))
        }
    }

    /// One word as it is now, for a view that holds an older copy of it.
    public func word(id: Int64) async throws -> Word? {
        try await writer.read { try Word.fetchOne($0, key: id) }
    }

    /// Words of one language, most frequent in your videos first. `search` matches anywhere in the lemma; `status`
    /// and `pos` (noun, verb...) narrow it, and either left nil means all.
    public func words(
        language: String, search: String = "", status: WordStatus? = nil, pos: PartOfSpeech? = nil, limit: Int = 50_000
    ) async throws -> [WordRow] {
        let escaped = search
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try await writer.read { db in
            try WordRow.fetchAll(db, sql: """
                SELECT words.*, (SELECT COUNT(*) FROM occurrences WHERE word_id = words.id) AS occurrence_count
                FROM words
                WHERE language = ?1 AND (status = ?2 OR (?2 IS NULL AND status != 'ignored')) AND (?5 IS NULL OR pos = ?5)
                  AND lemma LIKE ?3 ESCAPE '\\'
                ORDER BY occurrence_count DESC, lemma
                LIMIT ?4
                """, arguments: [language, status?.rawValue, "%\(escaped)%", limit, pos?.rawValue])
        }
    }

    public func examples(wordID: Int64, limit: Int = 20) async throws -> [ExampleLine] {
        try await writer.read { db in
            try ExampleLine.fetchAll(db, sql: """
                SELECT occurrences.surface, subtitles.id AS subtitle_id, subtitles.text, subtitles.start_time,
                       subtitles.end_time, videos.id AS video_id, videos.title AS video_title,
                       COALESCE(videos.audio_path, videos.video_path) AS media_path
                FROM occurrences
                JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                JOIN videos ON videos.id = subtitles.video_id
                WHERE occurrences.word_id = ?
                ORDER BY videos.imported_at DESC, subtitles.start_time
                LIMIT ?
                """, arguments: [wordID, limit])
        }
    }

    /// Back to an untouched word: out of the review queue and not marked known.
    public func markNew(wordID: Int64) async throws {
        try await updateWord(wordID) { word in
            word.status = .new
            word.stage = nil
            word.nextReview = nil
        }
    }

    public func dueCount(language: String, now: Date = Date()) async throws -> Int {
        try await writer.read { db in
            try Word.filter(Column("language") == language && Column("status") == WordStatus.learning.rawValue
                            && Column("next_review") <= now).fetchCount(db)
        }
    }
}

extension LangDatabase {
    public func subtitles(videoID: Int64) async throws -> [Subtitle] {
        try await writer.read { db in
            try Subtitle.filter(Column("video_id") == videoID).order(Column("idx")).fetchAll(db)
        }
    }

    public func video(id: Int64) async throws -> Video? {
        try await writer.read { try Video.fetchOne($0, key: id) }
    }
}

// MARK: Bulk actions

extension LangDatabase {
    private func chunks(_ ids: [Int64]) -> [[Int64]] {
        stride(from: 0, to: ids.count, by: 500).map { Array(ids[$0..<min($0 + 500, ids.count)]) }
    }

    /// Puts words into the review queue at stage 1, due now (or after `delay`, for a word just taught in a lesson and quizzed at once). Words already being learned or finished are left alone
    /// (their stage is not reset). Returns how many were added.
    @discardableResult
    public func startLearning(wordIDs: [Int64], now: Date = Date(), firstReviewAfter delay: TimeInterval = 0) async throws -> Int {
        try await writer.write { [chunks] db in
            var changed = 0
            for ids in chunks(wordIDs) {
                let starting = try Word.filter(keys: ids)
                    .filter(Column("status") != WordStatus.learning.rawValue && Column("status") != WordStatus.finished.rawValue)
                    .fetchAll(db).compactMap(\.id)
                for id in starting { try Self.bump(.learn, subject: id, at: now, in: db) }
                changed += try Word.filter(keys: ids)
                    .filter(Column("status") != WordStatus.learning.rawValue && Column("status") != WordStatus.finished.rawValue)
                    .updateAll(db,
                               Column("status").set(to: WordStatus.learning.rawValue),
                               Column("stage").set(to: SRSStage.stage1.rawValue),
                               Column("next_review").set(to: now.addingTimeInterval(delay)))
            }
            return changed
        }
    }

    /// Of `ids`, the words that are still new, in the order given: the only ones a lesson may teach. A word that was ignored,
    /// marked known or started since the list was made is left out, as it is from the day's lessons.
    public func stillNew(_ ids: [Int64]) async throws -> [Int64] {
        let found: Set<Int64> = try await writer.read { [chunks] db in
            var found = Set<Int64>()
            for part in chunks(ids) {
                found.formUnion(try Word.filter(keys: part).filter(Column("status") == WordStatus.new.rawValue).fetchAll(db).compactMap(\.id))
            }
            return found
        }
        return ids.filter { found.contains($0) }
    }

    /// The words as they are now, so that a bulk action can be undone. Ids that name no word are left out.
    public func snapshot(of wordIDs: [Int64]) async throws -> [Word] {
        try await writer.read { [chunks] db in
            try chunks(wordIDs).flatMap { try Word.filter(keys: $0).fetchAll(db) }
        }
    }

    /// Puts words back as a snapshot had them: status, stage and next review, and today's "started learning" and "marked
    /// known" tallies for the words the action had moved into those states. A word that a reset removed comes back with its
    /// old id. Returns how many were restored.
    @discardableResult
    public func restore(_ words: [Word], now: Date = Date()) async throws -> Int {
        try await writer.write { db in try Self.restore(words, in: db, now: now) }
    }

    /// The restore, inside the caller's transaction. With `onlyIfStill`, a word is put back only if it is still as that
    /// snapshot had it (see `WordChange`).
    static func restore(_ words: [Word], onlyIfStill after: [Word]? = nil, in db: Database, now: Date) throws -> Int {
        let afterByID = after.map { Dictionary(uniqueKeysWithValues: $0.compactMap { word in word.id.map { ($0, word) } }) }
        var restored = 0
        for var word in words {
            guard let id = word.id else { continue }
            let current = try Word.fetchOne(db, key: id)
            if let afterByID, !Self.sameProgress(current, afterByID[id]) { continue }
            if current?.status == .learning, word.status != .learning { try Self.unbump(.learn, subject: id, at: now, in: db) }
            if current?.status == .known, word.status != .known { try Self.unbump(.known, subject: id, at: now, in: db) }
            try word.save(db)
            restored += 1
        }
        return restored
    }

    /// Whether two copies of a word (or two absences) have the same status, stage and next review. The database keeps dates to
    /// the millisecond, so a copy from memory (with a varied interval) and one read back differ by less than that.
    static func sameProgress(_ a: Word?, _ b: Word?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        let sameReview: Bool
        switch (a.nextReview, b.nextReview) {
        case (nil, nil): sameReview = true
        case let (x?, y?): sameReview = abs(x.timeIntervalSince(y)) < 0.01
        default: sameReview = false
        }
        return a.status == b.status && a.stage == b.stage && sameReview
    }

    /// Marks words as known and takes them out of the review queue.
    @discardableResult
    public func markKnown(wordIDs: [Int64]) async throws -> Int {
        try await writer.write { [chunks] db in
            try chunks(wordIDs).reduce(0) { total, ids in
                let becoming = try Word.filter(keys: ids).filter(Column("status") != WordStatus.known.rawValue).fetchAll(db).compactMap(\.id)
                for id in becoming { try Self.bump(.known, subject: id, at: Date(), in: db) }
                return total + (try Word.filter(keys: ids).updateAll(
                    db, Column("status").set(to: WordStatus.known.rawValue),
                    Column("stage").set(to: nil), Column("next_review").set(to: nil)))
            }
        }
    }

    /// Sets words aside: out of the queue, out of the Words list, lessons and coverage, but kept (and so can be brought
    /// back with `markNew`). Returns how many changed.
    @discardableResult
    public func markIgnored(wordIDs: [Int64]) async throws -> Int {
        try await writer.write { [chunks] db in
            try chunks(wordIDs).reduce(0) { total, ids in
                total + (try Word.filter(keys: ids).filter(Column("status") != WordStatus.ignored.rawValue).updateAll(
                    db, Column("status").set(to: WordStatus.ignored.rawValue),
                    Column("stage").set(to: nil), Column("next_review").set(to: nil)))
            }
        }
    }

    /// Back to untouched: out of the queue, no stage, not known. A word that then appears in no line (a transcript
    /// mistake you have since edited away) is removed, as when a video is deleted; the rest stay as new words.
    /// Returns how many were reset.
    @discardableResult
    public func markNew(wordIDs: [Int64]) async throws -> Int {
        try await writer.write { [chunks] db in
            try chunks(wordIDs).reduce(0) { total, ids in
                let reset = try Word.filter(keys: ids).updateAll(
                    db, Column("status").set(to: WordStatus.new.rawValue),
                    Column("stage").set(to: nil), Column("next_review").set(to: nil))
                try db.execute(sql: """
                    DELETE FROM words
                    WHERE id IN (\(databaseQuestionMarks(count: ids.count))) AND status = 'new'
                      AND NOT EXISTS (SELECT 1 FROM occurrences WHERE occurrences.word_id = words.id)
                    """, arguments: StatementArguments(ids))
                return total + reset
            }
        }
    }
}

extension LangDatabase {
    /// Changes the title shown in the library. The files on disk keep their names; only the label changes.
    public func renameVideo(id: Int64, to title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LangError.emptyTitle }
        try await writer.write { db in
            guard var video = try Video.fetchOne(db, key: id) else { throw LangError.notFound }
            video.title = trimmed
            try video.update(db)
        }
    }
}

/// A word as the tokenizer and the word list both identify it.
public struct WordKey: Hashable, Sendable {
    public let lemma: String
    public let pos: PartOfSpeech

    public init(lemma: String, pos: PartOfSpeech) { self.lemma = lemma; self.pos = pos }
}

extension LangDatabase {
    /// The status of every word that appears in one video, for highlighting its subtitles.
    public func wordStatuses(videoID: Int64) async throws -> [WordKey: WordStatus] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT words.lemma, words.pos, words.status
                FROM occurrences
                JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                JOIN words ON words.id = occurrences.word_id
                WHERE subtitles.video_id = ?
                """, arguments: [videoID])
            var result: [WordKey: WordStatus] = [:]
            for row in rows {
                guard let pos = PartOfSpeech(rawValue: row["pos"]), let status = WordStatus(rawValue: row["status"]) else { continue }
                result[WordKey(lemma: row["lemma"], pos: pos)] = status
            }
            return result
        }
    }
}
