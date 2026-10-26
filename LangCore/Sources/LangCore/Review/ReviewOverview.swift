import Foundation
import GRDB

/// What the review page shows before a session: how many reviews are ready, when the rest come, and where your
/// words stand.
public struct ReviewOverview: Equatable, Sendable {
    public static let days = 7

    /// Reviews ready now.
    public var dueNow = 0
    /// Reviews per calendar day for the next `days` days, starting today. Today's count includes those already due.
    public var byDay = [Int](repeating: 0, count: days)
    /// Reviews due after the last day shown.
    public var afterThat = 0
    /// When the next review that isn't ready yet comes due.
    public var nextReview: Date?
    /// Words being learned at each stage 1...8.
    public var perStage = [Int](repeating: 0, count: 8)
    public var learning = 0, known = 0, finished = 0, new = 0

    public var isEmpty: Bool { learning + known + finished == 0 }
    public var scheduled: Int { byDay.reduce(0, +) + afterThat }
}

extension LangDatabase {
    public func reviewOverview(
        language: String, now: Date = Date(), calendar: Calendar = .current
    ) async throws -> ReviewOverview {
        try await writer.read { db in
            var overview = ReviewOverview()
            let today = calendar.startOfDay(for: now)

            let learning = try Row.fetchAll(db, sql: """
                SELECT stage, next_review FROM words WHERE language = ? AND status = 'learning'
                """, arguments: [language])
            for row in learning {
                if let stage: Int = row["stage"], (1...8).contains(stage) { overview.perStage[stage - 1] += 1 }
                guard let due: Date = row["next_review"] else { continue }
                if due <= now {
                    overview.dueNow += 1
                    overview.byDay[0] += 1
                    continue
                }
                if overview.nextReview.map({ due < $0 }) ?? true { overview.nextReview = due }
                let day = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
                if day < ReviewOverview.days { overview.byDay[max(0, day)] += 1 } else { overview.afterThat += 1 }
            }

            for row in try Row.fetchAll(db, sql: "SELECT status, COUNT(*) AS n FROM words WHERE language = ? GROUP BY status",
                                        arguments: [language]) {
                let n: Int = row["n"]
                switch WordStatus(rawValue: row["status"]) {
                case .learning: overview.learning = n
                case .known: overview.known = n
                case .finished: overview.finished = n
                case .new: overview.new = n
                case nil: break
                }
            }
            return overview
        }
    }
}
