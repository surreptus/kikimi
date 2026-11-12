import GRDB
import XCTest
@testable import LangCore

/// A rebuilt app, or a new copy over the old while it runs, replaces the bundled dictionary files under the open connections,
/// and SQLite then answers "disk I/O error" (error 10). The stores open the file again, once, and the lookup gives its answer.
final class ReopeningReaderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeDictionary(named name: String, words: [String]) throws -> URL {
        let url = dir.appending(path: name)
        try? FileManager.default.removeItem(at: url)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE entries (id INTEGER PRIMARY KEY, headword TEXT, reading TEXT, gloss TEXT, gender TEXT)")
            for word in words { try db.execute(sql: "INSERT INTO entries (headword, reading, gloss) VALUES (?, NULL, ?)", arguments: [word, "meaning of \(word)"]) }
        }
        try queue.close()
        return url
    }

    func testALookupSurvivesTheFileBeingReplacedByRename() async throws {
        let url = try makeDictionary(named: "d.sqlite", words: ["casa"])
        let store = try DictionaryStore(files: ["es": url])
        let before = try await store.lookup(language: "es", term: "casa", limit: 5)
        XCTAssertEqual(before.count, 1)
        // The new build's file, bigger, put in place by an atomic replace.
        let replacement = try makeDictionary(named: "new.sqlite", words: ["casa", "perro"] + (0..<400).map { "w\($0)" })
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
        let after = try await store.lookup(language: "es", term: "perro", limit: 5)
        XCTAssertEqual(after.map(\.headword), ["perro"], "opened again, so the new file is read")
    }

    func testALookupSurvivesTheFileBeingDeletedAndCopiedAgain() async throws {
        let url = try makeDictionary(named: "d.sqlite", words: ["casa"])
        let store = try DictionaryStore(files: ["es": url])
        _ = try await store.lookup(language: "es", term: "casa", limit: 5)
        let replacement = try makeDictionary(named: "new.sqlite", words: ["casa", "gato"] + (0..<400).map { "w\($0)" })
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: replacement, to: url)
        let after = try await store.lookup(language: "es", term: "gato", limit: 5)
        XCTAssertEqual(after.map(\.headword), ["gato"])
    }

    func testTheCountAlsoSurvives() async throws {
        let url = try makeDictionary(named: "d.sqlite", words: ["casa"])
        let store = try DictionaryStore(files: ["es": url])
        let before = try await store.entryCount(language: "es")
        XCTAssertEqual(before, 1)
        let replacement = try makeDictionary(named: "new.sqlite", words: (0..<400).map { "w\($0)" })
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
        let after = try await store.entryCount(language: "es")
        XCTAssertEqual(after, 400)
    }

    func testAnotherKindOfFailureIsStillReported() async throws {
        let url = try makeDictionary(named: "d.sqlite", words: ["casa"])
        let store = try DictionaryStore(files: ["es": url])
        _ = try await store.lookup(language: "es", term: "casa", limit: 5)
        // Gone for good: reopening cannot help, and the error is not hidden.
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await store.lookup(language: "es", term: "casa", limit: 5)
            XCTFail("a missing file should fail")
        } catch {}
    }

    func testTheKanjiFileSurvivesToo() async throws {
        func makeKanji(_ name: String, literal: String) throws -> URL {
            let url = dir.appending(path: name); try? FileManager.default.removeItem(at: url)
            let queue = try DatabaseQueue(path: url.path)
            try queue.write { db in
                try db.execute(sql: "CREATE TABLE kanji (literal TEXT PRIMARY KEY, on_yomi TEXT, kun_yomi TEXT, meaning TEXT, jlpt INTEGER, grade INTEGER)")
                try db.execute(sql: "INSERT INTO kanji VALUES (?, 'ゲツ', 'つき', 'moon', 5, 1)", arguments: [literal])
                for i in 0..<300 { try db.execute(sql: "INSERT INTO kanji VALUES (?, '', '', 'filler', NULL, NULL)", arguments: ["f\(i)"]) }
            }
            try queue.close(); return url
        }
        let url = try makeKanji("k.sqlite", literal: "月")
        let store = try KanjiStore(files: ["ja": url])
        let before = try await store.kanji(in: "月", language: "ja")
        XCTAssertEqual(before.count, 1)
        let replacement = try makeKanji("k2.sqlite", literal: "日")
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
        let after = try await store.kanji(in: "日", language: "ja")
        XCTAssertEqual(after.map(\.literal), ["日"])
    }
}
