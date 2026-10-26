import Foundation
import GRDB

/// What is tallied. Daily totals only, kept on this Mac.
public enum ActivityKind: String, Sendable {
    case listen            // seconds of a video played (subject: the video)
    case lookup            // a word's meaning opened on purpose (subject: the word)
    case learn             // a word put into your reviews (subject: the word)
    case known             // a word marked known (subject: the word)
    case review            // a review answered (subject: the word)
    case reviewCorrect = "review_correct"
}

enum ActivityDay {
    /// "2026-10-26": the local day, so a late-night session counts for the day it was.
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension LangDatabase {
    /// Adds `amount` to today's tally, inside the caller's transaction.
    static func bump(
        _ kind: ActivityKind, subject: Int64, amount: Double = 1, at date: Date, in db: Database, calendar: Calendar = .current
    ) throws {
        try db.execute(sql: """
            INSERT INTO activity (day, kind, subject, amount) VALUES (?, ?, ?, ?)
            ON CONFLICT (day, kind, subject) DO UPDATE SET amount = amount + excluded.amount
            """, arguments: [ActivityDay.string(date, calendar: calendar), kind.rawValue, subject, amount])
    }

    public func record(_ kind: ActivityKind, subject: Int64 = 0, amount: Double = 1, at date: Date = Date()) async throws {
        try await writer.write { try Self.bump(kind, subject: subject, amount: amount, at: date, in: $0) }
    }
}

/// What the Review page shows about your progress.
public struct LearningStats: Equatable, Sendable {
    public static let weeks = 8

    /// Words put into your reviews, per week, oldest first; the last is this week.
    public var startedPerWeek = [Int](repeating: 0, count: weeks)
    public var listenedThisWeek: TimeInterval = 0
    public var listenedTotal: TimeInterval = 0
    /// Reviews answered, and how many were right, over the last 30 days.
    public var reviews = 0
    public var reviewsCorrect = 0
    public var mostLookedUp: [LookupCount] = []

    public struct LookupCount: Equatable, Sendable {
        public var lemma: String
        public var count: Int
    }

    public var isEmpty: Bool {
        startedPerWeek.allSatisfy { $0 == 0 } && listenedTotal == 0 && reviews == 0 && mostLookedUp.isEmpty
    }

    public var accuracy: Double? { reviews > 0 ? Double(reviewsCorrect) / Double(reviews) : nil }
}

extension LangDatabase {
    public func learningStats(language: String, now: Date = Date(), calendar: Calendar = .current) async throws -> LearningStats {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let firstWeek = calendar.date(byAdding: .day, value: -7 * (LearningStats.weeks - 1), to: weekStart) ?? weekStart
        let weekStarts = (0..<LearningStats.weeks).map {
            ActivityDay.string(calendar.date(byAdding: .day, value: 7 * $0, to: firstWeek) ?? firstWeek, calendar: calendar)
        }
        let thisWeek = ActivityDay.string(weekStart, calendar: calendar)
        let thirtyDays = ActivityDay.string(calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now, calendar: calendar)

        return try await writer.read { db in
            var stats = LearningStats()
            for row in try Row.fetchAll(db, sql: """
                SELECT activity.day AS day, SUM(activity.amount) AS n FROM activity
                JOIN words ON words.id = activity.subject
                WHERE activity.kind = 'learn' AND words.language = ? AND activity.day >= ?
                GROUP BY activity.day
                """, arguments: [language, weekStarts[0]]) {
                let day: String = row["day"]
                if let index = weekStarts.lastIndex(where: { $0 <= day }) { stats.startedPerWeek[index] += Int(row["n"] as Double) }
            }
            let listened = try Row.fetchAll(db, sql: """
                SELECT activity.day AS day, SUM(activity.amount) AS s FROM activity
                JOIN videos ON videos.id = activity.subject
                WHERE activity.kind = 'listen' AND videos.language = ? GROUP BY activity.day
                """, arguments: [language])
            for row in listened {
                let seconds: Double = row["s"]
                stats.listenedTotal += seconds
                if (row["day"] as String) >= thisWeek { stats.listenedThisWeek += seconds }
            }
            for row in try Row.fetchAll(db, sql: """
                SELECT activity.kind AS kind, SUM(activity.amount) AS n FROM activity
                JOIN words ON words.id = activity.subject
                WHERE activity.kind IN ('review', 'review_correct') AND words.language = ? AND activity.day >= ?
                GROUP BY activity.kind
                """, arguments: [language, thirtyDays]) {
                let n = Int(row["n"] as Double)
                if (row["kind"] as String) == "review" { stats.reviews = n } else { stats.reviewsCorrect = n }
            }
            stats.mostLookedUp = try Row.fetchAll(db, sql: """
                SELECT words.lemma AS lemma, SUM(activity.amount) AS n FROM activity
                JOIN words ON words.id = activity.subject
                WHERE activity.kind = 'lookup' AND words.language = ?
                GROUP BY words.id ORDER BY n DESC, words.lemma LIMIT 5
                """, arguments: [language]).map { .init(lemma: $0["lemma"], count: Int($0["n"] as Double)) }
            return stats
        }
    }
}
