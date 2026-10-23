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

    /// Words of one language, most frequent in your videos first. `search` matches anywhere in the lemma.
    public func words(
        language: String, search: String = "", status: WordStatus? = nil, limit: Int = 50_000
    ) async throws -> [WordRow] {
        let escaped = search
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try await writer.read { db in
            try WordRow.fetchAll(db, sql: """
                SELECT words.*, (SELECT COUNT(*) FROM occurrences WHERE word_id = words.id) AS occurrence_count
                FROM words
                WHERE language = ?1 AND (?2 IS NULL OR status = ?2) AND lemma LIKE ?3 ESCAPE '\\'
                ORDER BY occurrence_count DESC, lemma
                LIMIT ?4
                """, arguments: [language, status?.rawValue, "%\(escaped)%", limit])
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

    /// Puts words into the review queue at apprentice 1, due now. Words already being learned or burned are left alone
    /// (their stage is not reset). Returns how many were added.
    @discardableResult
    public func startLearning(wordIDs: [Int64], now: Date = Date()) async throws -> Int {
        try await writer.write { [chunks] db in
            var changed = 0
            for ids in chunks(wordIDs) {
                changed += try Word.filter(keys: ids)
                    .filter(Column("status") != WordStatus.learning.rawValue && Column("status") != WordStatus.burned.rawValue)
                    .updateAll(db,
                               Column("status").set(to: WordStatus.learning.rawValue),
                               Column("stage").set(to: SRSStage.apprentice1.rawValue),
                               Column("next_review").set(to: now))
            }
            return changed
        }
    }

    /// Marks words as known and takes them out of the review queue.
    @discardableResult
    public func markKnown(wordIDs: [Int64]) async throws -> Int {
        try await writer.write { [chunks] db in
            try chunks(wordIDs).reduce(0) { total, ids in
                total + (try Word.filter(keys: ids).updateAll(
                    db, Column("status").set(to: WordStatus.known.rawValue),
                    Column("stage").set(to: nil), Column("next_review").set(to: nil)))
            }
        }
    }

    /// Back to untouched: out of the queue, no stage, not known.
    @discardableResult
    public func markNew(wordIDs: [Int64]) async throws -> Int {
        try await writer.write { [chunks] db in
            try chunks(wordIDs).reduce(0) { total, ids in
                total + (try Word.filter(keys: ids).updateAll(
                    db, Column("status").set(to: WordStatus.new.rawValue),
                    Column("stage").set(to: nil), Column("next_review").set(to: nil)))
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
