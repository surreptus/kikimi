import GRDB
import XCTest
@testable import LangCore

final class DictionaryTests: XCTestCase {
    private func builtFile(_ rows: [(String, String?, String)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "dict-\(UUID().uuidString).sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE entries (id INTEGER PRIMARY KEY, headword TEXT NOT NULL, reading TEXT, gloss TEXT NOT NULL)")
            for r in rows {
                try db.execute(sql: "INSERT INTO entries (headword, reading, gloss) VALUES (?, ?, ?)",
                               arguments: [r.0, r.1, r.2])
            }
        }
        return url
    }

    func testImportAssignsLanguageAndKeepsOrder() async throws {
        let file = try builtFile([("食べる", "たべる", "to eat"), ("日本", "にほん", "Japan")])
        defer { try? FileManager.default.removeItem(at: file) }
        let db = try LangDatabase()
        try await db.importDictionary(from: file, language: "ja")

        let all = try await db.writer.read { try DictionaryEntry.order(Column("id")).fetchAll($0) }
        XCTAssertEqual(all.map(\.headword), ["食べる", "日本"])
        XCTAssertEqual(Set(all.map(\.language)), ["ja"])
        let has = try await db.hasDictionary(language: "ja")
        let hasEs = try await db.hasDictionary(language: "es")
        XCTAssertTrue(has)
        XCTAssertFalse(hasEs)
    }

    func testReimportReplacesInsteadOfDuplicating() async throws {
        let file = try builtFile([("casa", nil, "house")])
        defer { try? FileManager.default.removeItem(at: file) }
        let db = try LangDatabase()
        try await db.importDictionary(from: file, language: "es")
        try await db.importDictionary(from: file, language: "es")
        let count = try await db.writer.read { try DictionaryEntry.fetchCount($0) }
        XCTAssertEqual(count, 1)
    }

    func testImportLeavesOtherLanguagesAlone() async throws {
        let es = try builtFile([("casa", nil, "house")])
        let ja = try builtFile([("家", "いえ", "house")])
        defer { [es, ja].forEach { try? FileManager.default.removeItem(at: $0) } }
        let db = try LangDatabase()
        try await db.importDictionary(from: es, language: "es")
        try await db.importDictionary(from: ja, language: "ja")
        try await db.importDictionary(from: es, language: "es")
        let jaEntries = try await db.lookup(language: "ja", term: "家")
        XCTAssertEqual(jaEntries.count, 1)
    }

    func testLookupByHeadwordOrReadingHeadwordFirst() async throws {
        let file = try builtFile([
            ("家", "いえ", "house"),            // reading match, earlier id
            ("いえ", "いえ", "no (kana form)"),   // headword match must still sort first
            ("犬", "いぬ", "dog"),
        ])
        defer { try? FileManager.default.removeItem(at: file) }
        let db = try LangDatabase()
        try await db.importDictionary(from: file, language: "ja")
        let hits = try await db.lookup(language: "ja", term: "いえ")
        XCTAssertEqual(hits.map(\.headword), ["いえ", "家"])
        let none = try await db.lookup(language: "es", term: "いえ")
        XCTAssertTrue(none.isEmpty)
    }

    func testMissingResourceIsReported() async throws {
        let db = try LangDatabase()
        do {
            try await db.importBundledDictionary(for: SpanishProfile(), bundle: Bundle(for: DictionaryTests.self))
            XCTFail("expected error")
        } catch DictionaryError.missingResource(let name) {
            XCTAssertEqual(name, "dictionary-es")
        }
    }

    /// Runs against the real built files (Scripts/build_dictionaries.sh); skipped until they exist.
    func testBundledDictionaries() async throws {
        let db = try LangDatabase()
        for (profile, term, expected) in [
            (JapaneseProfile() as any LanguageProfile, "食べる", "to eat"),
            (SpanishProfile(), "casa", "house"),
        ] {
            do {
                let imported = try await db.importBundledDictionary(for: profile)
                XCTAssertTrue(imported)
                let again = try await db.importBundledDictionary(for: profile)
                XCTAssertFalse(again)
            } catch DictionaryError.missingResource {
                throw XCTSkip("run Scripts/build_dictionaries.sh")
            }
            let hits = try await db.lookup(language: profile.code, term: term)
            XCTAssertTrue(hits.contains { $0.gloss.contains(expected) }, "\(term): \(hits.map(\.gloss))")
        }
    }

    func testV2MigrationAddsReadingIndexWithoutTouchingV1() throws {
        let db = try LangDatabase()
        let indexes = try db.writer.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type='index'") }
        XCTAssertTrue(indexes.contains("dictionary_reading"))
        XCTAssertTrue(indexes.contains("dictionary_lookup"))
    }
}
