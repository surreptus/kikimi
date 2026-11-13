import Foundation
import GRDB

/// One word offered while telling Kikimi which words you already know.
public struct CalibrationWord: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let lemma: String
    /// How many times it comes up in the video.
    public let seen: Int
}

/// Telling Kikimi which words of a video you already know, so a new learner's first coverage figure and first lessons start
/// from what they really know. The video's most-seen new words are shown in batches; you tick the ones you know, and the
/// pass stops once fewer than half of a batch are known, since further down the list it only gets harder. Only the words
/// you ticked are then known. The rules live here; the screen only draws them.
public enum Calibration {
    public static let batchSize = 20
    /// About 120 words, a few minutes at most.
    public static let maxBatches = 6
    /// A batch with a smaller share of known words than this is the last.
    public static let stopShare = 0.5

    /// The words in the groups they are shown in, most-seen first.
    public static func batches(of words: [CalibrationWord]) -> [[CalibrationWord]] {
        stride(from: 0, to: min(words.count, batchSize * maxBatches), by: batchSize).map {
            Array(words[$0..<min($0 + batchSize, words.count)])
        }
    }

    /// Whether the pass ends after this batch, because fewer than half of it is known to you.
    public static func endsAfter(_ batch: [CalibrationWord], known: Set<Int64>) -> Bool {
        guard !batch.isEmpty else { return true }
        return Double(batch.filter { known.contains($0.id) }.count) / Double(batch.count) < stopShare
    }

    /// The words to mark known: every word shown that you ticked.
    public static func known(shown: [[CalibrationWord]], ticked: Set<Int64>) -> [Int64] {
        shown.flatMap { $0 }.map(\.id).filter { ticked.contains($0) }
    }
}

extension LangDatabase {
    /// The new words of a video that come up most, to ask about: only words still new, so a word you have ignored, marked
    /// known or started is never offered.
    public func calibrationWords(videoID: Int64, limit: Int = Calibration.batchSize * Calibration.maxBatches) async throws -> [CalibrationWord] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT words.id AS id, words.lemma AS lemma, COUNT(occurrences.id) AS n
                FROM occurrences
                JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                JOIN words ON words.id = occurrences.word_id
                WHERE subtitles.video_id = ? AND words.status = 'new'
                GROUP BY words.id ORDER BY n DESC, words.lemma LIMIT ?
                """, arguments: [videoID, limit]).map { CalibrationWord(id: $0["id"], lemma: $0["lemma"], seen: $0["n"]) }
        }
    }
}
