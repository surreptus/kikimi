import XCTest
import GRDB
@testable import LangCore

final class ReviewOverviewTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    /// 10:00 UTC on a fixed day.
    private let now: Date = {
        let midnight: TimeInterval = 1_759_968_000   // 2025-10-09 00:00 UTC, a Thursday
        return Date(timeIntervalSince1970: midnight + 10 * 3600)
    }()

    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

    private func library() async throws -> LangDatabase {
        let db = try LangDatabase()
        try await db.writer.write { d in
            func add(_ lemma: String, _ status: WordStatus, _ stage: SRSStage? = nil, due: Date? = nil, language: String = "es") throws {
                var w = Word(language: language, lemma: lemma, pos: .noun, status: status, stage: stage, nextReview: due); try w.insert(d)
            }
            try add("ya", .learning, .stage1, due: hours(-3))        // overdue: ready now
            try add("ahora", .learning, .stage2, due: hours(0))      // due exactly now
            try add("luego", .learning, .stage2, due: hours(5))      // later today (15:00)
            try add("mañana", .learning, .stage5, due: hours(20))    // tomorrow (06:00)
            try add("pronto", .learning, .stage8, due: hours(24 * 3 + 2))   // three days on
            try add("lejos", .learning, .stage8, due: hours(24 * 30))       // beyond the week
            try add("sabida", .known)
            try add("vieja", .finished, .finished)
            try add("nueva", .new)
            try add("no", .learning, .stage3, due: hours(1), language: "ja")   // another language
        }
        return db
    }

    func testCountsWhatIsReadyAndWhatIsComing() async throws {
        let o = try await library().reviewOverview(language: "es", now: now, calendar: calendar)
        XCTAssertEqual(o.dueNow, 2)
        XCTAssertEqual(o.byDay, [3, 1, 0, 1, 0, 0, 0], "today includes the two ready now and one later today")
        XCTAssertEqual(o.afterThat, 1)
        XCTAssertEqual(o.scheduled, 6)
        XCTAssertEqual(o.nextReview, hours(5), "the first one that isn't ready yet")
    }

    func testCountsWordsByStageAndStatus() async throws {
        let o = try await library().reviewOverview(language: "es", now: now, calendar: calendar)
        XCTAssertEqual(o.perStage, [1, 2, 0, 0, 1, 0, 0, 2])
        XCTAssertEqual([o.learning, o.known, o.finished, o.new], [6, 1, 1, 1])
        XCTAssertFalse(o.isEmpty)
    }

    func testAnEmptyLibraryIsEmpty() async throws {
        let o = try await LangDatabase().reviewOverview(language: "es", now: now, calendar: calendar)
        XCTAssertTrue(o.isEmpty)
        XCTAssertNil(o.nextReview)
        XCTAssertEqual(o.byDay, [Int](repeating: 0, count: 7))
    }
}
