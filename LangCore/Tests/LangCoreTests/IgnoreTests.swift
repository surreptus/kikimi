import GRDB
import XCTest
@testable import LangCore

final class IgnoreTests: XCTestCase {
    private func library() async throws -> (LangDatabase, [String: Int64], Int64) {
        let db = try LangDatabase()
        var ids: [String: Int64] = [:]
        var videoID: Int64 = 0
        try await db.writer.write { d in
            var video = Video(language: "es", title: "v", contentHash: "h", videoPath: "h/v.mov", duration: 9); try video.insert(d)
            videoID = video.id!
            var line = Subtitle(videoId: video.id!, idx: 0, startTime: 0, endTime: 1, text: "casa ? perro"); try line.insert(d)
            for (lemma, status) in [("casa", WordStatus.known), ("?", .new), ("perro", .new)] {
                var w = Word(language: "es", lemma: lemma, pos: lemma == "?" ? .other : .noun, status: status); try w.insert(d)
                ids[lemma] = w.id!
                var o = Occurrence(wordId: w.id!, subtitleId: line.id!, surface: lemma); try o.insert(d)
            }
        }
        return (db, ids, videoID)
    }

    func testAnIgnoredWordLeavesTheListsLessonsAndCoverageButIsKept() async throws {
        let (db, ids, videoID) = try await library()
        var changed = try await db.markIgnored(wordIDs: [ids["?"]!])
        XCTAssertEqual(changed, 1)
        changed = try await db.markIgnored(wordIDs: [ids["?"]!])
        XCTAssertEqual(changed, 0, "already ignored")

        let all = try await db.words(language: "es").map(\.word.lemma)
        XCTAssertFalse(all.contains("?"), "hidden from the Words list unless asked for")
        let ignored = try await db.words(language: "es", status: .ignored).map(\.word.lemma)
        XCTAssertEqual(ignored, ["?"], "kept, and shown when the filter asks for it")

        let lessons = try await db.dailyLessons(language: "es", contentPOS: [.noun, .other], perDay: 15)
        XCTAssertEqual(lessons.wordIDs, [ids["perro"]!], "never offered as a lesson")

        let coverage = try await db.coverage(forVideo: videoID)
        XCTAssertEqual([coverage?.totalWords, coverage?.knownWords], [2, 1], "not counted against the video")
        let goal = try await db.wordsToReach(target: 0.9, inVideo: videoID)
        XCTAssertEqual(goal?.words.map(\.lemma), ["perro"], "not suggested either")
    }

    func testRestoringBringsAnIgnoredWordBackAsNew() async throws {
        let (db, ids, _) = try await library()
        try await db.markIgnored(wordIDs: [ids["?"]!])
        let reset = try await db.markNew(wordIDs: [ids["?"]!])
        XCTAssertEqual(reset, 1)
        let word = try await db.word(id: ids["?"]!)
        XCTAssertEqual(word?.status, .new)
    }
}

final class IgnoreBackupTests: XCTestCase {
    func testAnIgnoredWordSurvivesABackupAndRestore() async throws {
        let source = try LangDatabase()
        try await source.writer.write { d in
            var w = Word(language: "es", lemma: "?", pos: .other, status: .ignored); try w.insert(d)
        }
        let backup = try await source.exportProgress(settings: [:])
        let target = try LangDatabase()
        try await target.writer.write { d in
            var w = Word(language: "es", lemma: "?", pos: .other); try w.insert(d)   // the same word, found again in a new library
        }
        try await target.importProgress(backup)
        let status = try await target.writer.read { try String.fetchOne($0, sql: "SELECT status FROM words WHERE lemma = '?'") }
        XCTAssertEqual(status, WordStatus.ignored.rawValue)
    }
}
