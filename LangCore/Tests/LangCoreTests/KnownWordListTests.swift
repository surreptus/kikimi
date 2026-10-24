import XCTest
import GRDB
@testable import LangCore

final class KnownWordListTests: XCTestCase {
    func testParsesOneWordPerLineAndTheFirstColumnOfCSVAndTSV() {
        let text = "\u{FEFF}casa\r\n  perro  \n# a comment\n\n\"gato\",cat,animal\nmesa\tmesa (table)\nlibro;book\nCasa\n"
        XCTAssertEqual(KnownWordList.parse(text), ["casa", "perro", "gato", "mesa", "libro"],
                       "order kept, comment and blank lines skipped, quotes and extra columns dropped, repeats (even other case) removed")
        XCTAssertEqual(KnownWordList.parse(""), [])
        XCTAssertEqual(KnownWordList.parse("食べる\n友達,ともだち\n"), ["食べる", "友達"])
    }

    private func library() async throws -> LangDatabase {
        let db = try LangDatabase()
        try await db.writer.write { d in
            for (language, lemma, pos, status, stage) in [
                ("es", "casa", PartOfSpeech.noun, WordStatus.new, SRSStage?.none),
                ("es", "casa", .verb, .new, nil),                              // same spelling, another part of speech
                ("es", "perro", .noun, .learning, .apprentice2),
                ("es", "mesa", .noun, .known, nil),
                ("es", "libro", .noun, .burned, .burned),
                ("es", "árbol", .noun, .new, nil),
                ("ja", "casa", .noun, .new, nil),                              // another language: never touched
            ] {
                var w = Word(language: language, lemma: lemma, pos: pos, status: status, stage: stage, nextReview: stage == nil ? nil : Date()); try w.insert(d)
            }
        }
        return db
    }

    private func status(_ db: LangDatabase, _ lemma: String, language: String = "es") async throws -> [WordStatus] {
        try await db.writer.read { try Word.filter(Column("language") == language && Column("lemma") == lemma).fetchAll($0).map(\.status) }
    }

    func testMarksNewAndLearningWordsKnownAndLeavesFinishedOnesAlone() async throws {
        let db = try await library()
        let report = try await db.markKnown(lemmas: ["casa", "perro", "mesa", "libro", "gato"], language: "es")
        XCTAssertEqual(report.listed, 5)
        XCTAssertEqual(report.marked, 3, "both casa rows and perro")
        XCTAssertEqual(report.fromLearning, 1, "perro was being learned")
        XCTAssertEqual(report.alreadyKnown, 2, "mesa and libro")
        XCTAssertEqual(report.notInLibrary, 1, "gato isn't in the library, and isn't invented")
        let casa = try await status(db, "casa"); XCTAssertEqual(casa, [.known, .known])
        let perro = try await status(db, "perro"); XCTAssertEqual(perro, [.known])
        let libro = try await status(db, "libro"); XCTAssertEqual(libro, [.burned], "finished stays finished")
        let gato = try await status(db, "gato"); XCTAssertEqual(gato, [])
        let perroRow = try await db.writer.read { try Word.filter(Column("lemma") == "perro").fetchOne($0)! }
        XCTAssertNil(perroRow.stage); XCTAssertNil(perroRow.nextReview, "it leaves the review queue")
    }

    func testOnlyTheChosenLanguageIsTouched() async throws {
        let db = try await library()
        try await db.markKnown(lemmas: ["casa"], language: "es")
        let ja = try await status(db, "casa", language: "ja")
        XCTAssertEqual(ja, [.new])
    }

    func testMatchingIgnoresCaseAndKeepsAccents() async throws {
        let db = try await library()
        let report = try await db.markKnown(lemmas: ["CASA", "Árbol"], language: "es")
        XCTAssertEqual(report.marked, 3)
        let arbol = try await status(db, "árbol"); XCTAssertEqual(arbol, [.known])
    }

    func testADryRunCountsWithoutChangingAnything() async throws {
        let db = try await library()
        let preview = try await db.markKnown(lemmas: ["casa", "perro"], language: "es", dryRun: true)
        XCTAssertEqual(preview.marked, 3)
        let casa = try await status(db, "casa"); XCTAssertEqual(casa, [.new, .new])
        let perro = try await status(db, "perro"); XCTAssertEqual(perro, [.learning])
        let real = try await db.markKnown(lemmas: ["casa", "perro"], language: "es")
        XCTAssertEqual(preview, real, "the preview says exactly what the real run does")
    }

    func testRunningTheSameListAgainChangesNothing() async throws {
        let db = try await library()
        try await db.markKnown(lemmas: ["casa", "perro"], language: "es")
        let again = try await db.markKnown(lemmas: ["casa", "perro"], language: "es")
        XCTAssertEqual(again.marked, 0)
        XCTAssertEqual(again.alreadyKnown, 2)
    }
}
