import XCTest
import GRDB
@testable import LangCore

final class WordTypeFilterTests: XCTestCase {
    private func library() async throws -> LangDatabase {
        let db = try LangDatabase()
        try await db.writer.write { db in
            for (lemma, pos, status) in [
                ("casa", PartOfSpeech.noun, WordStatus.new), ("mesa", .noun, .learning), ("comer", .verb, .new),
                ("correr", .verb, .known), ("grande", .adjective, .new), ("muy", .adverb, .new),
            ] {
                var w = Word(language: "es", lemma: lemma, pos: pos, status: status); try w.insert(db)
            }
            var other = Word(language: "ja", lemma: "家", pos: .noun); try other.insert(db)
        }
        return db
    }

    func testFilteringByTypeKeepsOnlyThatType() async throws {
        let db = try await library()
        let verbs = try await db.words(language: "es", pos: .verb).map(\.word.lemma)
        XCTAssertEqual(Set(verbs), ["comer", "correr"])
        let nouns = try await db.words(language: "es", pos: .noun).map(\.word.lemma)
        XCTAssertEqual(Set(nouns), ["casa", "mesa"])
        let adjectives = try await db.words(language: "es", pos: .adjective).map(\.word.lemma)
        XCTAssertEqual(adjectives, ["grande"])
    }

    func testNoTypeMeansEveryType() async throws {
        let db = try await library()
        let all = try await db.words(language: "es").count
        XCTAssertEqual(all, 6)
    }

    func testTypeCombinesWithStatusAndSearch() async throws {
        let db = try await library()
        let newVerbs = try await db.words(language: "es", status: .new, pos: .verb).map(\.word.lemma)
        XCTAssertEqual(newVerbs, ["comer"])
        let searched = try await db.words(language: "es", search: "r", pos: .verb).map(\.word.lemma)
        XCTAssertEqual(Set(searched), ["comer", "correr"])
        let none = try await db.words(language: "es", search: "casa", pos: .verb)
        XCTAssertTrue(none.isEmpty, "casa is a noun")
    }

    func testTypeStaysWithinTheLanguage() async throws {
        let db = try await library()
        let ja = try await db.words(language: "ja", pos: .noun).map(\.word.lemma)
        XCTAssertEqual(ja, ["家"])
    }

    func testTheTypeFilterAppliesToTheDictionaryFormFallbackToo() async throws {
        let env = try LangEnvironment(
            root: FileManager.default.temporaryDirectory.appending(path: "wt-\(UUID().uuidString)"),
            defaults: UserDefaults(suiteName: "wt-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([])),
            dictionaries: TestDictionaries.store(["es": [("correr", nil, "to run")], "ja": [("家", "いえ", "house")]]))
        defer { try? FileManager.default.removeItem(at: env.root) }
        try await env.database.writer.write { d in var w = Word(language: "es", lemma: "correr", pos: .verb); try w.insert(d) }
        let spanish = SpanishProfile()
        // "corremos" has no word of its own; its dictionary form "correr" is a verb, so it is found as one...
        let asVerb = await env.searchWords("corremos", profile: spanish, pos: .verb)
        XCTAssertEqual(asVerb.map(\.word.lemma), ["correr"])
        // ...and is not found when only nouns are wanted.
        let asNoun = await env.searchWords("corremos", profile: spanish, pos: .noun)
        XCTAssertTrue(asNoun.isEmpty)
    }
}
