import Foundation
import GRDB

/// How many new words a day Kikimi offers as lessons, for each language. 0 turns lessons off.
public struct DailyLessonPreference: @unchecked Sendable {
    public static let standard = 15
    public static let choices = [0, 5, 10, 15, 20, 30, 50]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func perDay(for profile: any LanguageProfile) -> Int {
        defaults.object(forKey: key(profile)) as? Int ?? Self.standard
    }

    public func setPerDay(_ count: Int, for profile: any LanguageProfile) {
        defaults.set(count == Self.standard ? nil : count, forKey: key(profile))
    }

    private func key(_ profile: any LanguageProfile) -> String { "newWordsPerDay.\(profile.code)" }
}

/// Today's lessons: the new words that matter most in your videos, as many as the day's allowance still has room for.
public struct DailyLessons: Equatable, Sendable {
    /// Most useful first.
    public var wordIDs: [Int64] = []
    /// Words started today by any route, which use up the allowance.
    public var startedToday = 0
    public var perDay = 0
    /// Reviews are over the limit, so no new words are offered until they are caught up.
    public var heldBack = false

    public var isOff: Bool { perDay == 0 }
}

extension LangDatabase {
    /// Reviews due beyond which no new words are offered, so a backlog is cleared before it grows.
    public static let lessonReviewLimit = 100

    /// Words started today (by lesson, on the Words page or from a video's goal) in `language`.
    public func startedToday(language: String, now: Date = Date(), calendar: Calendar = .current) async throws -> Int {
        let day = ActivityDay.string(now, calendar: calendar)
        return try await writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM activity JOIN words ON words.id = activity.subject
                WHERE activity.kind = 'learn' AND activity.day = ? AND words.language = ?
                """, arguments: [day, language]) ?? 0
        }
    }

    /// The day's lessons. Only new content words that have a line in one of your videos, ranked by how many lines they
    /// are in. Unused lessons do not carry over: the list is worked out afresh each day from what is left of the allowance.
    public func dailyLessons(
        language: String, contentPOS: Set<PartOfSpeech>, perDay: Int, now: Date = Date(), calendar: Calendar = .current
    ) async throws -> DailyLessons {
        var lessons = DailyLessons(perDay: perDay)
        guard perDay > 0 else { return lessons }
        lessons.startedToday = try await startedToday(language: language, now: now, calendar: calendar)
        let room = perDay - lessons.startedToday
        guard room > 0 else { return lessons }
        if try await dueCount(language: language, now: now) > Self.lessonReviewLimit {
            lessons.heldBack = true
            return lessons
        }
        let parts = contentPOS.map(\.rawValue).sorted()
        let marks = parts.map { _ in "?" }.joined(separator: ",")
        lessons.wordIDs = try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT words.id FROM words JOIN occurrences ON occurrences.word_id = words.id
                WHERE words.language = ? AND words.status = 'new' AND words.pos IN (\(marks))
                GROUP BY words.id ORDER BY COUNT(DISTINCT occurrences.subtitle_id) DESC, words.lemma LIMIT ?
                """, arguments: StatementArguments([language] + parts) + [room])
        }
        return lessons
    }

    /// A lesson's word with a sentence from your videos.
    public func lessonCard(wordID: Int64, language: String) async throws -> ReviewCard? {
        guard let word = try await writer.read({ try Word.fetchOne($0, key: wordID) }) else { return nil }
        let entries = try await lookup(language: language, term: word.lemma, limit: 3)
        let example = ExamplePicker.pick(from: try await examples(wordID: wordID, limit: 50))
        return ReviewCard(word: word, entries: entries, example: example)
    }
}
