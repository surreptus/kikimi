import GRDB
import XCTest
@testable import LangCore

final class DictionaryTests: XCTestCase {
    func testLookupByHeadwordOrReadingHeadwordFirst() async throws {
        let db = try LangDatabase(dictionaries: TestDictionaries.store(["ja": [
            ("家", "いえ", "house"),                 // reading match, earlier id
            ("いえ", "いえ", "no (kana form)"),      // headword match must still sort first
            ("犬", "いぬ", "dog"),
        ]]))
        let hits = try await db.lookup(language: "ja", term: "いえ")
        XCTAssertEqual(hits.map(\.headword), ["いえ", "家"])
        XCTAssertEqual(hits.map(\.language), ["ja", "ja"], "entries carry the language they were read for")
        let none = try await db.lookup(language: "ja", term: "xyz")
        XCTAssertTrue(none.isEmpty)
    }

    func testEachLanguageHasItsOwnDictionaryAndLimitsApply() async throws {
        let db = try LangDatabase(dictionaries: TestDictionaries.store([
            "es": [("casa", nil, "house"), ("casa", nil, "home"), ("casa", nil, "household")],
            "ja": [("家", "いえ", "house")],
        ]))
        let limited = try await db.lookup(language: "es", term: "casa", limit: 2)
        XCTAssertEqual(limited.map(\.gloss), ["house", "home"], "file order is kept (common words first)")
        let crossed = try await db.lookup(language: "ja", term: "casa")
        XCTAssertTrue(crossed.isEmpty, "a word in one language's dictionary is not in another's")
        let unknownLanguage = try await db.lookup(language: "fr", term: "maison")
        XCTAssertTrue(unknownLanguage.isEmpty, "a language without a dictionary just finds nothing")
    }

    func testCountsAndLanguages() async throws {
        let store = try TestDictionaries.store(["es": [("a", nil, "x"), ("b", nil, "y")], "ja": [("c", nil, "z")]])
        XCTAssertEqual(store.languages, ["es", "ja"])
        let es = try await store.entryCount(language: "es")
        let none = try await store.entryCount(language: "fr")
        XCTAssertEqual(es, 2)
        XCTAssertEqual(none, 0)
        XCTAssertTrue(DictionaryStore.empty.languages.isEmpty)
    }

    /// The app bundle is read-only (and sandboxed), so the store must work without being able to write at all.
    func testReadsAFileInAReadOnlyFolderWithoutChangingIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = try TestDictionaries.makeFile([("casa", nil, "house")], in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let before = try Data(contentsOf: file)

        let store = try DictionaryStore(files: ["es": file])
        for _ in 0..<5 { _ = try await store.lookup(language: "es", term: "casa", limit: 5) }
        let hits = try await store.lookup(language: "es", term: "casa", limit: 5)

        XCTAssertEqual(hits.map(\.gloss), ["house"])
        XCTAssertEqual(try Data(contentsOf: file), before, "reading never writes")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [file.lastPathComponent],
                       "no journal or temporary files appear next to it")
    }

    func testTheDatabaseNoLongerHoldsADictionary() async throws {
        let db = try LangDatabase(dictionaries: TestDictionaries.store(["es": [("casa", nil, "house")]]))
        let tables = try await db.writer.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type='table'") }
        XCTAssertFalse(tables.contains("dictionary"))
        XCTAssertTrue(tables.isSuperset(of: ["videos", "subtitles", "words", "occurrences"]))
    }

    func testMissingResourceIsReported() throws {
        do {
            _ = try DictionaryStore.bundled(for: [SpanishProfile()], bundle: Bundle(for: DictionaryTests.self))
            XCTFail("expected error")
        } catch DictionaryError.missingResource(let name) {
            XCTAssertEqual(name, "dictionary-es")
        }
    }

    /// Against the real built files (Scripts/build_dictionaries.sh): they open in place, are indexed, and answer.
    func testBundledDictionaries() async throws {
        let store: DictionaryStore
        do { store = try DictionaryStore.bundled(for: LanguageProfiles.all) }
        catch DictionaryError.missingResource { throw XCTSkip("run Scripts/build_dictionaries.sh") }

        let db = try LangDatabase(dictionaries: store)
        for (language, term, expected) in [("ja", "食べる", "to eat"), ("ja", "たべる", "to eat"), ("es", "casa", "house")] {
            let hits = try await db.lookup(language: language, term: term)
            XCTAssertTrue(hits.contains { $0.gloss.contains(expected) }, "\(term): \(hits.map(\.gloss))")
        }
        // Spellings shared by several entries must lead with the usual word (秋 is あき, not the とき of 時).
        for (term, reading, gloss) in [("秋", "あき", "autumn"), ("米", "こめ", "rice"), ("彼", "かれ", "he")] {
            let first = try await db.lookup(language: "ja", term: term, limit: 5).first
            XCTAssertEqual(first?.reading, reading, "\(term): \(String(describing: first?.gloss))")
            XCTAssertTrue(first?.gloss.contains(gloss) == true, "\(term): \(String(describing: first?.gloss))")
        }
        let ja = try await store.entryCount(language: "ja")
        XCTAssertGreaterThan(ja, 100_000)

        // Indexed, so a lookup doesn't scan 335,000 rows.
        let started = Date()
        for _ in 0..<200 { _ = try await store.lookup(language: "ja", term: "静か", limit: 5) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0, "200 lookups")
    }
}

final class DropCopiedDictionaryMigrationTests: XCTestCase {
    /// A database as an earlier version left it: the dictionary copied in, plus the user's own data.
    private func oldDatabase(at path: String, entries: Int) throws {
        let queue = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        LangMigrations.register(in: &migrator)
        try migrator.migrate(queue, upTo: "v2-dictionary-reading-index")
        try queue.write { db in
            for i in 0..<entries {
                try db.execute(sql: "INSERT INTO dictionary (language, headword, reading, gloss) VALUES ('ja', ?, ?, ?)",
                               arguments: ["語\(i)", "ご\(i)", String(repeating: "meaning ", count: 18) + "\(i)"])
            }
            var word = Word(language: "ja", lemma: "友達", pos: .noun, status: .learning, stage: .apprentice2)
            try word.insert(db)
        }
    }

    func testOpeningAnOldDatabaseDropsTheCopyKeepsYourDataAndReturnsTheSpace() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "old-\(UUID().uuidString).sqlite").path
        addTeardownBlock { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        try oldDatabase(at: path, entries: 80_000)
        let before = try FileManager.default.attributesOfItem(atPath: path)[.size] as! Int
        XCTAssertGreaterThan(before, 10_000_000, "the copied dictionary made it large")

        var wordLemma: String?
        do {
            let db = try LangDatabase(path: path)   // migrates v3 and reclaims the space
            let tables = try await db.writer.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type='table'") }
            XCTAssertFalse(tables.contains("dictionary"))
            wordLemma = try await db.writer.read { try Word.fetchOne($0)?.lemma }
        }
        XCTAssertEqual(wordLemma, "友達", "your words are untouched")

        // The connections are closed now, so the file has been checkpointed down to its real size.
        let after = try FileManager.default.attributesOfItem(atPath: path)[.size] as! Int
        XCTAssertLessThan(after, before / 10, "was \(before) bytes, now \(after)")
    }

    func testAFreshDatabaseNeedsNoReclaimAndMigratesTwice() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "fresh-\(UUID().uuidString).sqlite").path
        addTeardownBlock { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        _ = try LangDatabase(path: path)
        _ = try LangDatabase(path: path)   // reopening runs no migration again and does not fail
    }
}
