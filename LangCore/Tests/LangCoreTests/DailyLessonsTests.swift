import GRDB
import XCTest
@testable import LangCore

final class DailyLessonsTests: XCTestCase {
    private let content: Set<PartOfSpeech> = [.noun, .verb]

    private func library() async throws -> (LangDatabase, [String: Int64]) {
        let db = try LangDatabase()
        var ids: [String: Int64] = [:]
        try await db.writer.write { d in
            var video = Video(language: "es", title: "v", contentHash: "h", videoPath: "h/v.mov", duration: 100)
            try video.insert(d)
            var lines: [Int64] = []
            for i in 0..<4 {
                var line = Subtitle(videoId: video.id!, idx: i, startTime: Double(i), endTime: Double(i) + 1, text: "t\(i)")
                try line.insert(d); lines.append(line.id!)
            }
            // casa in 3 lines, perro in 2, gato in 1, y (a particle) in 4, libro is known, mesa is learning, luz has no line
            let specs: [(String, PartOfSpeech, WordStatus, Int)] = [
                ("casa", .noun, .new, 3), ("perro", .noun, .new, 2), ("gato", .noun, .new, 1), ("y", .other, .new, 4),
                ("libro", .noun, .known, 4), ("mesa", .noun, .learning, 2), ("luz", .noun, .new, 0)]
            for (lemma, pos, status, count) in specs {
                var w = Word(language: "es", lemma: lemma, pos: pos, status: status,
                             stage: status == .learning ? .stage1 : nil, nextReview: status == .learning ? Date.distantFuture : nil)
                try w.insert(d); ids[lemma] = w.id!
                for line in lines.prefix(count) {
                    var o = Occurrence(wordId: w.id!, subtitleId: line, surface: lemma); try o.insert(d)
                }
            }
        }
        return (db, ids)
    }

    func testTheMostHeardNewContentWordsComeFirstAndOthersAreLeftOut() async throws {
        let (db, ids) = try await library()
        let lessons = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 2)
        XCTAssertEqual(lessons.wordIDs, [ids["casa"]!, ids["perro"]!], "known, learning, particle and line-less words are skipped")
        let all = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 15)
        XCTAssertEqual(all.wordIDs, [ids["casa"]!, ids["perro"]!, ids["gato"]!])
    }

    func testAnyWordStartedTodayUsesUpTheAllowance() async throws {
        let (db, ids) = try await library()
        try await db.startLearning(wordIDs: [ids["casa"]!])
        let lessons = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 2)
        XCTAssertEqual(lessons.startedToday, 1)
        XCTAssertEqual(lessons.wordIDs, [ids["perro"]!], "one lesson left of two")
        try await db.startLearning(wordIDs: [ids["perro"]!])
        let none = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 2)
        XCTAssertTrue(none.wordIDs.isEmpty)
    }

    func testUnusedLessonsDoNotCarryOverToTheNextDay() async throws {
        let (db, ids) = try await library()
        let yesterday = Date().addingTimeInterval(-86_400 * 2)
        try await db.startLearning(wordIDs: [ids["casa"]!, ids["perro"]!], now: yesterday)
        let lessons = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 2)
        XCTAssertEqual(lessons.startedToday, 0, "yesterday's starts do not count today")
        XCTAssertEqual(lessons.wordIDs, [ids["gato"]!])
    }

    func testNothingIsOfferedWhenOffOrWhenReviewsArePilingUp() async throws {
        let (db, ids) = try await library()
        let off = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 0)
        XCTAssertTrue(off.isOff)
        XCTAssertTrue(off.wordIDs.isEmpty)
        try await db.writer.write { d in
            for i in 0...LangDatabase.lessonReviewLimit {
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun, status: .learning, stage: .stage1,
                             nextReview: Date().addingTimeInterval(-60))
                try w.insert(d)
            }
        }
        let held = try await db.dailyLessons(language: "es", contentPOS: content, perDay: 15)
        XCTAssertTrue(held.heldBack)
        XCTAssertTrue(held.wordIDs.isEmpty)
        _ = ids
    }

    func testThePreferenceDefaultsToFifteenAndZeroTurnsItOff() {
        let defaults = UserDefaults(suiteName: "DailyLessonsTests.\(UUID().uuidString)")!
        let preference = DailyLessonPreference(defaults: defaults)
        let es = LanguageProfiles.all.first { $0.code == "es" }!
        XCTAssertEqual(preference.perDay(for: es), 15)
        preference.setPerDay(0, for: es)
        XCTAssertEqual(preference.perDay(for: es), 0)
        preference.setPerDay(15, for: es)
        XCTAssertEqual(preference.perDay(for: es), 15)
    }
}
