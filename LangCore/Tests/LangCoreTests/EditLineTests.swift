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

    func testAnEmptyLineIsRefusedAndAMissingOneReported() async throws {
        let (db, line) = try await library()
        do { try await db.editSubtitle(id: line, text: "   ", profile: spanish); XCTFail() }
        catch { XCTAssertEqual(error as? LangError, .emptyLine) }
        do { try await db.editSubtitle(id: 9999, text: "hola", profile: spanish); XCTFail() }
        catch { XCTAssertEqual(error as? LangError, .notFound) }
    }
}
