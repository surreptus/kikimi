import GRDB
import XCTest
@testable import LangCore

final class LemmaSearchTests: XCTestCase {
    func testInflectedFormsMapToDictionaryForms() {
        let es = SpanishProfile()
        XCTAssertEqual(es.lemmas(of: "corremos"), ["correr"])
        XCTAssertEqual(es.lemmas(of: "casas"), ["casa"])
        XCTAssertEqual(es.lemmas(of: "La casa grande"), ["casa", "grande"])
        XCTAssertEqual(es.lemmas(of: ""), [])
        let ja = JapaneseProfile()
        XCTAssertEqual(ja.lemmas(of: "食べた"), ["食べる"], "particles and endings are not words to look up")
        XCTAssertEqual(ja.lemmas(of: "行きました"), ["行く"])
    }

    private func environment() throws -> (LangEnvironment, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "lemma-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try LangEnvironment(root: root, defaults: UserDefaults(suiteName: "lemma-\(UUID().uuidString)")!), root)
    }

    func testDictionaryLookupFallsBackToTheDictionaryForm() async throws {
        let (env, _) = try environment()
        try await env.database.writer.write { db in
            var run = DictionaryEntry(language: "es", headword: "correr", gloss: "1. (verb) to run"); try run.insert(db)
            var eat = DictionaryEntry(language: "ja", headword: "食べる", reading: "たべる", gloss: "1. (v1) to eat"); try eat.insert(db)
        }
        let es = SpanishProfile(), ja = JapaneseProfile()
        let inflected = await env.lookupWord("corremos", profile: es)
        XCTAssertEqual(inflected.map(\.headword), ["correr"])
        let past = await env.lookupWord("食べた", profile: ja)
        XCTAssertEqual(past.map(\.headword), ["食べる"])
        let exact = await env.lookupWord("correr", profile: es)
        XCTAssertEqual(exact.map(\.headword), ["correr"])
        let nothing = await env.lookupWord("xyzzy", profile: es)
        XCTAssertTrue(nothing.isEmpty)
    }

    func testAnExactEntryBeatsTheFallback() async throws {
        let (env, _) = try environment()
        try await env.database.writer.write { db in
            var a = DictionaryEntry(language: "es", headword: "corremos", gloss: "form entry"); try a.insert(db)
            var b = DictionaryEntry(language: "es", headword: "correr", gloss: "base entry"); try b.insert(db)
        }
        let hits = await env.lookupWord("corremos", profile: SpanishProfile())
        XCTAssertEqual(hits.map(\.headword), ["corremos"])
    }

    func testWordSearchFindsTheDictionaryFormOfWhatYouTyped() async throws {
        let (env, _) = try environment()
        try await env.database.writer.write { db in
            for lemma in ["correr", "casa", "corral"] { var w = Word(language: "es", lemma: lemma, pos: .noun); try w.insert(db) }
        }
        let es = SpanishProfile()
        let inflected = await env.searchWords("corremos", profile: es)
        XCTAssertEqual(inflected.map(\.word.lemma), ["correr"])
        let partial = await env.searchWords("corr", profile: es)
        XCTAssertEqual(Set(partial.map(\.word.lemma)), ["correr", "corral"], "a plain partial match still works")
        let all = await env.searchWords("", profile: es)
        XCTAssertEqual(all.count, 3)
        let none = await env.searchWords("zzz", profile: es)
        XCTAssertTrue(none.isEmpty)
    }

    func testWordSearchRespectsTheStatusFilter() async throws {
        let (env, _) = try environment()
        try await env.database.writer.write { db in
            var w = Word(language: "es", lemma: "correr", pos: .verb, status: .known); try w.insert(db)
        }
        let es = SpanishProfile()
        let hidden = await env.searchWords("corremos", profile: es, status: .learning)
        XCTAssertTrue(hidden.isEmpty)
        let shown = await env.searchWords("corremos", profile: es, status: .known)
        XCTAssertEqual(shown.count, 1)
    }
}
