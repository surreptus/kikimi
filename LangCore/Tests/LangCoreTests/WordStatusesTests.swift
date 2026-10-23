import GRDB
import XCTest
@testable import LangCore

final class WordStatusesTests: XCTestCase {
    private func importVideo(_ db: LangDatabase, hash: String, text: String) async throws -> Video {
        let es = SpanishProfile()
        return try await db.saveImport(
            video: Video(language: "es", title: hash, contentHash: hash, videoPath: "\(hash)/v", duration: 5),
            subtitles: [(segment: TranscriptSegment(start: 0, end: 1, text: text), tokens: es.contentWords(in: text))])
    }

    private func id(_ db: LangDatabase, _ lemma: String) async throws -> Int64 {
        try await db.writer.read { try Word.filter(Column("lemma") == lemma).fetchOne($0)!.id! }
    }

    func testStatusesCoverEveryWordInTheVideoAndOnlyThatVideo() async throws {
        let db = try LangDatabase()
        let a = try await importVideo(db, hash: "a", text: "La casa es grande.")
        _ = try await importVideo(db, hash: "b", text: "El perro corre rápidamente.")

        try await db.startLearning(wordID: try await id(db, "casa"))
        try await db.markKnown(wordID: try await id(db, "grande"))

        let statuses = try await db.wordStatuses(videoID: a.id!)
        XCTAssertEqual(statuses[WordKey(lemma: "casa", pos: .noun)], .learning)
        XCTAssertEqual(statuses[WordKey(lemma: "grande", pos: .adjective)], .known)
        XCTAssertEqual(statuses[WordKey(lemma: "ser", pos: .verb)], .new, "untouched words are included, as new")
        XCTAssertNil(statuses[WordKey(lemma: "perro", pos: .noun)], "words from other videos are not")
    }

    func testAWordSharedByTwoVideosShowsTheSameStatusInBoth() async throws {
        let db = try LangDatabase()
        let a = try await importVideo(db, hash: "a", text: "La casa es grande.")
        let b = try await importVideo(db, hash: "b", text: "Mi casa nueva.")
        try await db.markKnown(wordID: try await id(db, "casa"))
        let inA = try await db.wordStatuses(videoID: a.id!)
        let inB = try await db.wordStatuses(videoID: b.id!)
        XCTAssertEqual(inA[WordKey(lemma: "casa", pos: .noun)], .known)
        XCTAssertEqual(inB[WordKey(lemma: "casa", pos: .noun)], .known)
    }

    func testStatusesFollowChanges() async throws {
        let db = try LangDatabase()
        let video = try await importVideo(db, hash: "a", text: "La casa es grande.")
        let casa = try await id(db, "casa")
        try await db.startLearning(wordID: casa)
        var statuses = try await db.wordStatuses(videoID: video.id!)
        XCTAssertEqual(statuses[WordKey(lemma: "casa", pos: .noun)], .learning)
        try await db.markNew(wordID: casa)
        statuses = try await db.wordStatuses(videoID: video.id!)
        XCTAssertEqual(statuses[WordKey(lemma: "casa", pos: .noun)], .new)
    }

    func testAVideoWithNoWordsOrUnknownIdIsEmpty() async throws {
        let db = try LangDatabase()
        let empty = try await db.saveImport(
            video: Video(language: "es", title: "x", contentHash: "x", videoPath: "x/v", duration: 1), subtitles: [])
        let none = try await db.wordStatuses(videoID: empty.id!)
        XCTAssertTrue(none.isEmpty)
        let unknown = try await db.wordStatuses(videoID: 999)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testTokensFromLineSegmentsMatchTheStoredWords() async throws {
        // The player looks statuses up by the segment tokens' lemma and part of speech, so they must agree.
        let db = try LangDatabase()
        let text = "La casa es grande."
        let video = try await importVideo(db, hash: "a", text: text)
        let statuses = try await db.wordStatuses(videoID: video.id!)
        let es = SpanishProfile()
        let contentTokens = es.lineSegments(in: text).compactMap(\.token).filter { es.contentPOS.contains($0.pos) }
        XCTAssertFalse(contentTokens.isEmpty)
        for token in contentTokens {
            XCTAssertNotNil(statuses[WordKey(lemma: token.lemma, pos: token.pos)], "\(token.surface) should be found")
        }
    }
}
