import Foundation
import GRDB

extension SRSStage {
    /// A word being learned counts as known for coverage once its reviews are a week or more apart (stage 5 and up):
    /// by then you recognise it, even though you are still reviewing it.
    public var isEstablished: Bool { rawValue >= SRSStage.stage5.rawValue }
}

/// How easy a video should be to follow, from how many of its content words you know.
///
/// Coverage here counts content words only (nouns, verbs, adjectives, adverbs), since small words like articles and
/// particles aren't kept. They make up roughly half of any speech and are nearly always known, so the share of all
/// words you understand is higher than the figure shown: about 90% of content words is roughly 95% of everything,
/// which is around the point listening becomes comfortable.
public enum LevelFit: Int, Equatable, Sendable, CaseIterable {
    case hard, stretch, comfortable, easy

    public static let hardBelow = 0.80
    public static let stretchBelow = 0.88
    public static let easyFrom = 0.98
    /// Where a video is most worth watching: mostly understood, with a little new to learn.
    public static let ideal = 0.93

    public init(fraction: Double) {
        switch fraction {
        case ..<Self.hardBelow: self = .hard
        case ..<Self.stretchBelow: self = .stretch
        case ..<Self.easyFrom: self = .comfortable
        default: self = .easy
        }
    }

    public var title: String {
        switch self {
        case .hard: String(localized: "Hard", bundle: .module)
        case .stretch: String(localized: "A stretch", bundle: .module)
        case .comfortable: String(localized: "Comfortable", bundle: .module)
        case .easy: String(localized: "Easy", bundle: .module)
        }
    }

    /// Lower sorts first when asking "what should I watch next": comfortable, then a stretch, then easy (little to
    /// learn), then hard.
    fileprivate var order: Int {
        switch self {
        case .comfortable: 0
        case .stretch: 1
        case .easy: 2
        case .hard: 3
        }
    }
}

/// How much of one video you already know.
public struct VideoCoverage: Equatable, Sendable {
    public var videoID: Int64
    /// Content words in the video, each counted once for every line it appears in.
    public var totalWords: Int
    /// How many of those are words you know (see `SRSStage.isEstablished`).
    public var knownWords: Int

    public init(videoID: Int64, totalWords: Int, knownWords: Int) {
        self.videoID = videoID; self.totalWords = totalWords; self.knownWords = knownWords
    }

    public var unknownWords: Int { totalWords - knownWords }
    /// 0 to 1. A video with no words in it (silence, or nothing the tokenizer kept) reads as 0.
    public var fraction: Double { totalWords == 0 ? 0 : Double(knownWords) / Double(totalWords) }
    /// nil when there are no words to judge by.
    public var fit: LevelFit? { totalWords == 0 ? nil : LevelFit(fraction: fraction) }

    /// Orders videos from the best next watch to the worst: by fit, then by how close to `LevelFit.ideal`.
    public static func bestFirst(_ a: VideoCoverage, _ b: VideoCoverage) -> Bool {
        switch (a.fit, b.fit) {
        case (nil, nil): return a.videoID < b.videoID
        case (nil, _): return false          // videos with nothing to judge go last
        case (_, nil): return true
        case (let x?, let y?):
            if x.order != y.order { return x.order < y.order }
            let da = abs(a.fraction - LevelFit.ideal), db = abs(b.fraction - LevelFit.ideal)
            return da != db ? da < db : a.videoID < b.videoID
        }
    }
}

/// The words that would take a video to a coverage you chose, most common in the video first.
public struct CoverageGoal: Equatable, Sendable {
    public var current: VideoCoverage
    public var target: Double
    /// The shortest list, most frequent first, that reaches `target`. Empty if it is already reached.
    public var words: [Entry]
    /// What coverage would be if you knew every word on the list.
    public var reachedFraction: Double

    public struct Entry: Equatable, Sendable {
        public var wordID: Int64
        public var lemma: String
        public var status: WordStatus
        /// How many lines of this video contain it.
        public var occurrences: Int
    }

    public var isReached: Bool { current.fraction >= target }
    /// Words on the list you haven't started learning; the ones worth adding to your reviews.
    public var notStarted: [Entry] { words.filter { $0.status == .new } }
}

private let knownCondition = """
    (words.status IN ('known', 'burned') OR (words.status = 'learning' AND words.stage >= \(SRSStage.stage5.rawValue)))
    """

extension LangDatabase {
    /// Coverage for every video (of one language, or all), keyed by video id.
    public func videoCoverage(language: String? = nil) async throws -> [Int64: VideoCoverage] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT videos.id AS video_id, COUNT(occurrences.id) AS total,
                       COALESCE(SUM(CASE WHEN \(knownCondition) THEN 1 ELSE 0 END), 0) AS known
                FROM videos
                LEFT JOIN subtitles ON subtitles.video_id = videos.id
                LEFT JOIN occurrences ON occurrences.subtitle_id = subtitles.id
                LEFT JOIN words ON words.id = occurrences.word_id
                WHERE (?1 IS NULL OR videos.language = ?1)
                GROUP BY videos.id
                """, arguments: [language])
            var result: [Int64: VideoCoverage] = [:]
            for row in rows {
                let id: Int64 = row["video_id"]
                result[id] = VideoCoverage(videoID: id, totalWords: row["total"], knownWords: row["known"])
            }
            return result
        }
    }

    public func coverage(forVideo id: Int64) async throws -> VideoCoverage? {
        let all = try await videoCoverage()
        return all[id]
    }

    /// The fewest new words, commonest in this video first, that would take it to `target` (0 to 1).
    public func wordsToReach(target: Double, inVideo id: Int64, limit: Int = 500) async throws -> CoverageGoal? {
        guard let current = try await coverage(forVideo: id) else { return nil }
        let unknown: [CoverageGoal.Entry] = try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT words.id AS word_id, words.lemma AS lemma, words.status AS status, COUNT(occurrences.id) AS n
                FROM occurrences
                JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                JOIN words ON words.id = occurrences.word_id
                WHERE subtitles.video_id = ? AND NOT \(knownCondition)
                GROUP BY words.id
                ORDER BY n DESC, words.lemma
                """, arguments: [id]).map {
                CoverageGoal.Entry(
                    wordID: $0["word_id"], lemma: $0["lemma"],
                    status: WordStatus(rawValue: $0["status"]) ?? .new, occurrences: $0["n"])
            }
        }
        var goal = CoverageGoal(current: current, target: target, words: [], reachedFraction: current.fraction)
        guard current.totalWords > 0, current.fraction < target else { return goal }
        var known = current.knownWords
        for entry in unknown.prefix(limit) {
            goal.words.append(entry)
            known += entry.occurrences
            goal.reachedFraction = Double(known) / Double(current.totalWords)
            if goal.reachedFraction >= target { break }
        }
        return goal
    }
}
