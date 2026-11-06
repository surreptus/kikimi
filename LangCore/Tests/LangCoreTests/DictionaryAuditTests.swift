import GRDB
import XCTest
@testable import LangCore

/// Checks that run over the real bundled dictionaries, to find a whole kind of mistake at once instead of one word at a time.
final class DictionaryAuditTests: XCTestCase {
    private func read<T>(_ resource: String, _ body: (Database) throws -> T) throws -> T {
        let url = try XCTUnwrap(DictionaryStore.bundledURL(resource), resource)
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: url.path, configuration: configuration).read(body)
    }

    /// Words that have a plain entry and also a capitalised or all-capitals one (dorado and Dorado, no and NO). The lookup
    /// must give the plain entry first when the video spells the word plain, and the capitalised one when it is capitalised.
    func testEveryCapitalClashPicksTheEntryTheSpellingNames() async throws {
        for profile in [SpanishProfile(), FrenchProfile(), GermanProfile()] as [any LanguageProfile] {
            let code = profile.code, resource = profile.dictionarySource.resourceName
            let store = try DictionaryStore.bundled(for: [profile])
            // One pass: spellings that differ only by case, grouped (a correlated lookup per row would take minutes).
            let clashes: [(plain: String, capital: String?)] = try read(resource) { db in
                try Row.fetchAll(db, sql: """
                    SELECT lower(headword) AS plain, group_concat(headword, char(9)) AS forms FROM entries
                    WHERE headword NOT LIKE '% %' GROUP BY lower(headword)
                    HAVING count(*) > 1 AND sum(headword = lower(headword)) > 0
                    """).map { row in
                    let plain: String = row["plain"]
                    let forms = (row["forms"] as String).split(separator: "\t").map(String.init)
                    return (plain, forms.first { $0 != plain && $0.first?.isUppercase == true && $0.dropFirst() == plain.dropFirst() })
                }
            }
            XCTAssertFalse(clashes.isEmpty, "\(code) has words with a capitalised twin")
            var wrong: [String] = []
            for clash in clashes {
                let plain = try await store.lookup(language: code, term: clash.plain, limit: 10, surface: clash.plain)
                if plain.first?.headword != clash.plain { wrong.append("\(clash.plain) spelt plain led by \(plain.first?.headword ?? "nothing")") }
                if let capital = clash.capital {
                    let named = try await store.lookup(language: code, term: clash.plain, limit: 10, surface: capital)
                    if named.first?.headword != capital { wrong.append("\(capital) spelt capitalised led by \(named.first?.headword ?? "nothing")") }
                }
            }
            XCTAssertEqual(wrong, [], "\(code): \(clashes.count) clashing words checked")
        }
    }

    /// Spellings of a common Spanish verb (3,000 spread through the dictionary's forms table, which says which verb each is;
    /// LANGCORE_AUDIT=1 tries 15,000 and prints what it finds). Every spelling (the dictionary's forms table, which says
    /// which verb each is) goes through the tokenizer in a short sentence, and the result is sorted:
    ///  - read as a verb, and the right one: fine;
    ///  - read as a verb, but another verb (what the table was built to prevent): a failure;
    ///  - not read as a verb at all: counted, with examples, since a verb stored as a noun has the wrong lemma and kind.
    /// LANGCORE_AUDIT_SAMPLE sets the number. Last measured (6 Nov 2026, 15,741 spellings): 99.85% read as the right verb, none
    /// as another verb, and 24 not as a verb at all, all rare (voseo forms such as tamizás, forms with a pronoun attached).
    func testSpanishVerbFormsAreReadAsTheirVerbs() throws {
        let env = ProcessInfo.processInfo.environment
        let full = env["LANGCORE_AUDIT"] == "1"
        let sample = Int(env["LANGCORE_AUDIT_SAMPLE"] ?? "") ?? (full ? 15_000 : 3_000)
        let forms: [(spelling: String, lemmas: [String])] = try read("dictionary-es") { db in
            try Row.fetchAll(db, sql: "SELECT form, lemmas FROM forms ORDER BY form").map {
                let lemmas: String = $0["lemmas"]
                return ($0["form"], lemmas.split(separator: ",").map { String($0.split(separator: ":")[0]) })
            }
        }
        let headwords: Set<String> = try read("dictionary-es") { db in Set(try String.fetchAll(db, sql: "SELECT headword FROM entries")) }
        let step = max(1, forms.count / sample)
        let tokenizer = SpanishProfile().tokenizer
        var tried = 0, right = 0, otherVerb: [String] = [], notVerb: [String: Int] = [:], missed: [String] = []
        for index in stride(from: 0, to: forms.count, by: step) {
            let (spelling, lemmas) = forms[index]
            guard !spelling.contains(" ") else { continue }
            tried += 1
            guard let token = tokenizer.tokens(in: "Él \(spelling) aquí.").first(where: { $0.surface.lowercased() == spelling }) else { continue }
            if token.pos == .verb {
                if lemmas.contains(token.lemma) { right += 1 } else { otherVerb.append("\(spelling)→\(token.lemma) (want \(lemmas[0]))") }
            } else {
                notVerb[String(describing: token.pos), default: 0] += 1
                // A spelling that is not a word of its own can only be a verb form: reading it as anything else is a miss.
                if !headwords.contains(spelling) { missed.append("\(spelling) read as \(token.pos) \(token.lemma) (want \(lemmas[0]))") }
            }
        }
        if full {
            print("AUDIT forms in the table: \(forms.count); tried \(tried)")
            print("AUDIT read as the right verb: \(right); as another verb: \(otherVerb.count); not as a verb: \(notVerb.values.reduce(0, +)) \(notVerb)")
            print("AUDIT not a headword of its own yet not read as a verb: \(missed.count)")
            for line in otherVerb.prefix(30) { print("AUDIT OTHER VERB \(line)") }
            for line in missed.shuffled().prefix(40) { print("AUDIT MISSED \(line)") }
        }
        XCTAssertGreaterThan(tried, 1_000)
        XCTAssertEqual(otherVerb, [], "a verb form read as a different verb")
        XCTAssertGreaterThan(Double(right) / Double(tried), 0.99, "nearly every form of a common verb is read as that verb")
    }
}
