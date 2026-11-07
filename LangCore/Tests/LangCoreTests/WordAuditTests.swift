import GRDB
import XCTest
@testable import LangCore

/// Opt in with LANGCORE_AUDIT_DB=<a copy of a Kikimi database>: prints the most-seen words in it as the app would show
/// them (lemma, kind, how it is spelt in the videos, and the first meaning the dictionary gives), so a person can read down
/// the list for wrong meanings. LANGCORE_AUDIT_LANG picks the language (default es) and LANGCORE_AUDIT_TOP how many (default 300).
/// Read-only: it works on a copy, and nothing is written anywhere.
final class WordAuditTests: XCTestCase {
    func testPrintTheMostSeenWordsWithTheirFirstMeaning() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LANGCORE_AUDIT_DB"] != nil, "set LANGCORE_AUDIT_DB")
        let path = try XCTUnwrap(env["LANGCORE_AUDIT_DB"])
        let language = env["LANGCORE_AUDIT_LANG"] ?? "es"
        let top = Int(env["LANGCORE_AUDIT_TOP"] ?? "") ?? 300
        let profile = try XCTUnwrap(LanguageProfiles.profile(for: language))
        let db = try LangDatabase(path: path, dictionaries: DictionaryStore.bundled(for: [profile]))
        let rows: [(id: Int64, lemma: String, pos: String, status: String, seen: Int)] = try await db.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT words.id AS id, words.lemma AS lemma, words.pos AS pos, words.status AS status, COUNT(occurrences.id) AS n
                FROM words JOIN occurrences ON occurrences.word_id = words.id
                WHERE words.language = ? GROUP BY words.id ORDER BY n DESC, words.lemma LIMIT ?
                """, arguments: [language, top]).map { ($0["id"], $0["lemma"], $0["pos"], $0["status"], $0["n"]) }
        }
        for row in rows {
            let examples = try await db.examples(wordID: row.id, limit: 50)
            let surface = DictionaryStore.commonSurface(of: examples.map(\.surface))
            let entries = try await db.lookup(language: language, term: row.lemma, limit: 3, surface: surface)
            let gloss = entries.first.map { "[\($0.headword)] " + $0.shortGloss } ?? "NO ENTRY"
            print("WORD \(row.seen)x \(row.lemma) (\(row.pos), \(row.status)) as \"\(surface ?? "")\" → \(gloss.prefix(90))")
        }
    }
}
