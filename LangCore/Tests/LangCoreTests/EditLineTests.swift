import GRDB
import XCTest
@testable import LangCore

final class EditLineTests: XCTestCase {
    private let spanish = SpanishProfile()

    private func library() async throws -> (db: LangDatabase, line: Int64) {
        let db = try LangDatabase()
        let video = try await db.saveImport(
            video: Video(language: "es", title: "v", contentHash: "h", videoPath: "h/video.mov", duration: 10),
            subtitles: [(TranscriptSegment(start: 0, end: 2, text: "La casa es grande"),
                         spanish.contentWords(in: "La casa es grande")),
                        (TranscriptSegment(start: 3, end: 5, text: "Otra casa"), spanish.contentWords(in: "Otra casa"))])
        let line = try await db.subtitles(videoID: video.id!).first!.id!
        return (db, line)
    }

    private func lemmas(_ db: LangDatabase, line: Int64) async throws -> Set<String> {
        try await db.writer.read {
            try String.fetchSet($0, sql: """
                SELECT words.lemma FROM occurrences JOIN words ON words.id = occurrences.word_id
                WHERE occurrences.subtitle_id = ?
                """, arguments: [line])
        }
    }

    func testTheLineAndItsWordsAreReplaced() async throws {
        let (db, line) = try await library()
        let before = try await lemmas(db, line: line)
        XCTAssertTrue(before.contains("casa"))

        let saved = try await db.editSubtitle(id: line, text: "  El perro corre rápido  ", profile: spanish)
        XCTAssertEqual(saved.text, "El perro corre rápido", "trimmed")
        let after = try await lemmas(db, line: line)
        XCTAssertTrue(after.contains("perro"))
        XCTAssertFalse(after.contains("casa"))
        let text = try await db.writer.read { try String.fetchOne($0, sql: "SELECT text FROM subtitles WHERE id = ?", arguments: [line]) }
        XCTAssertEqual(text, "El perro corre rápido")
    }

    func testWordsYouWorkedOnAreKeptButUnusedNewOnesGo() async throws {
        let (db, line) = try await library()
        let grande = try await db.writer.read { try Word.filter(Column("lemma") == "grande").fetchOne($0)!.id! }
        try await db.markKnown(wordID: grande)

        try await db.editSubtitle(id: line, text: "Un perro", profile: spanish)
        let survivors = try await db.writer.read { try String.fetchSet($0, sql: "SELECT lemma FROM words") }
        XCTAssertTrue(survivors.contains("grande"), "marked known, so it stays even though no line has it now")
        XCTAssertTrue(survivors.contains("casa"), "still in the other line")
        XCTAssertFalse(survivors.contains("ser"), "new and now nowhere: removed")
    }

    func testTimingCanBeMovedButNotNonsense() async throws {
        let (db, line) = try await library()
        let moved = try await db.editSubtitle(id: line, text: "La casa es grande", start: 0.4, end: 2.6, profile: spanish)
        XCTAssertEqual([moved.startTime, moved.endTime], [0.4, 2.6])

        let onlyEnd = try await db.editSubtitle(id: line, text: "La casa es grande", end: 3.0, profile: spanish)
        XCTAssertEqual([onlyEnd.startTime, onlyEnd.endTime], [0.4, 3.0], "a timing left out keeps its value")

        for bad in [(-1.0, 2.0), (2.0, 2.0), (3.0, 1.0), (0.0, 99.0)] {
            do { try await db.editSubtitle(id: line, text: "x casa", start: bad.0, end: bad.1, profile: spanish); XCTFail("\(bad)") }
            catch { XCTAssertEqual(error as? LangError, .badTiming, "\(bad)") }
        }
        let still = try await db.subtitles(videoID: 1).first
        XCTAssertEqual(still?.startTime, 0.4, "a refused change leaves the line as it was")
    }

    func testCountsLinesAndVideosAWordIsSeenIn() async throws {
        let (db, _) = try await library()   // "casa" is in two lines of one video
        let casa = try await db.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        let grande = try await db.writer.read { try Word.filter(Column("lemma") == "grande").fetchOne($0)!.id! }
        let seen = try await db.seen(wordID: casa)
        XCTAssertEqual(seen, WordSeen(lines: 2, videos: 1))
        let once = try await db.seen(wordID: grande)
        XCTAssertEqual(once, WordSeen(lines: 1, videos: 1))
        let none = try await db.seen(wordID: 9999)
        XCTAssertEqual(none, WordSeen(lines: 0, videos: 0))
    }

    func testAnEmptyLineIsRefusedAndAMissingOneReported() async throws {
        let (db, line) = try await library()
        do { try await db.editSubtitle(id: line, text: "   ", profile: spanish); XCTFail() }
        catch { XCTAssertEqual(error as? LangError, .emptyLine) }
        do { try await db.editSubtitle(id: 9999, text: "hola", profile: spanish); XCTFail() }
        catch { XCTAssertEqual(error as? LangError, .notFound) }
    }
}
