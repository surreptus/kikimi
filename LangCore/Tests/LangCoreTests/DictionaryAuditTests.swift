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

    private struct VerbAudit {
        var tried = 0, right = 0, lemmaRight = 0
        var otherVerb: [String] = [], missed: [String] = []
        var notVerb: [String: Int] = [:]
    }

    /// Spellings of a common verb (3,000 spread through the dictionary's forms table, which says which verb each is;
    /// LANGCORE_AUDIT=1 tries many more and prints what it finds). Every spelling goes through the tokenizer in a short
    /// sentence, and the result is sorted:
    ///  - read as a verb, and the right one: fine;
    ///  - read as a verb, but another verb (what the table was built to prevent): a failure;
    ///  - not read as a verb at all: counted, with examples, since a verb stored as a noun has the wrong lemma and kind.
    /// LANGCORE_AUDIT_SAMPLE sets the number.
    private func auditVerbForms(_ profile: any LanguageProfile, carrier: (String) -> String, fullSample: Int) throws -> VerbAudit {
        let env = ProcessInfo.processInfo.environment
        let full = env["LANGCORE_AUDIT"] == "1"
        let sample = Int(env["LANGCORE_AUDIT_SAMPLE"] ?? "") ?? (full ? fullSample : 3_000)
        let resource = profile.dictionarySource.resourceName
        let forms: [(spelling: String, lemmas: [String])] = try read(resource) { db in
            try Row.fetchAll(db, sql: "SELECT form, lemmas FROM forms ORDER BY form").map {
                let lemmas: String = $0["lemmas"]
                return ($0["form"], lemmas.split(separator: ",").map { String($0.split(separator: ":")[0]) })
            }
        }
        // Lower case: German nouns are capitalised in text, so "Stich" is a word of its own where the test sentence has "stich".
        let headwords: Set<String> = try read(resource) { db in Set(try String.fetchAll(db, sql: "SELECT headword FROM entries").map { $0.lowercased() }) }
        let step = max(1, forms.count / sample)
        var audit = VerbAudit()
        for index in stride(from: 0, to: forms.count, by: step) {
            let (spelling, lemmas) = forms[index]
            guard !spelling.contains(" ") else { continue }
            audit.tried += 1
            guard let token = profile.tokenizer.tokens(in: carrier(spelling)).first(where: { $0.surface.lowercased() == spelling }) else { continue }
            if lemmas.contains(token.lemma) { audit.lemmaRight += 1 }
            if token.pos == .verb {
                if lemmas.contains(token.lemma) { audit.right += 1 } else { audit.otherVerb.append("\(spelling)→\(token.lemma) (want \(lemmas[0]))") }
            } else {
                audit.notVerb[String(describing: token.pos), default: 0] += 1
                // A spelling that is not a word of its own can only be a verb form: reading it as anything else is a miss.
                if !headwords.contains(spelling) { audit.missed.append("\(spelling) read as \(token.pos) \(token.lemma) (want \(lemmas[0]))") }
            }
        }
        if full {
            print("AUDIT \(profile.code): forms in the table \(forms.count); tried \(audit.tried)")
            print("AUDIT \(profile.code): lemma right \(audit.lemmaRight); right verb \(audit.right); another verb \(audit.otherVerb.count); not a verb \(audit.notVerb.values.reduce(0, +)) \(audit.notVerb); not a headword either \(audit.missed.count)")
            for line in audit.otherVerb.prefix(30) { print("AUDIT \(profile.code) OTHER VERB \(line)") }
            for line in audit.missed.shuffled().prefix(40) { print("AUDIT \(profile.code) MISSED \(line)") }
        }
        return audit
    }

    /// `minimum` is the share of spellings whose lemma comes out right. Where the tagger calls a form something other than a
    /// verb (a participle used as an adjective or an adverb, which is often right) the lemma can still be the verb.
    private func check(_ audit: VerbAudit, minimum: Double = 0.99) {
        XCTAssertGreaterThan(audit.tried, 1_000)
        XCTAssertEqual(audit.otherVerb, [], "a verb form read as a different verb")
        XCTAssertGreaterThan(Double(audit.lemmaRight) / Double(audit.tried), minimum, "nearly every form of a common verb gets that verb as its lemma")
    }

    /// A pronoun that goes with the ending, so the sentence is one a person could say: "Er richtest" is not.
    private static func germanCarrier(_ form: String) -> String {
        let pronoun: String
        switch true {
        case form.hasSuffix("st"): pronoun = "Du"
        case form.hasSuffix("en") || form.hasSuffix("ern") || form.hasSuffix("eln"): pronoun = "Wir"
        case form.hasSuffix("e"): pronoun = "Ich"
        default: pronoun = "Er"
        }
        return "\(pronoun) \(form) hier."
    }

    /// Last measured (6 Nov 2026): Spanish 99.85% read as the right verb (15,741 spellings, none as another verb; the rest are
    /// rare, such as voseo forms like tamizás), French 99.8% (17,671) and German 99.2% for the lemma (14,148).
    func testSpanishVerbFormsAreReadAsTheirVerbs() throws {
        check(try auditVerbForms(SpanishProfile(), carrier: { "Él \($0) aquí." }, fullSample: 15_000))
    }

    func testFrenchVerbFormsAreReadAsTheirVerbs() throws {
        check(try auditVerbForms(FrenchProfile(), carrier: { "Il \($0) ici." }, fullSample: 15_000), minimum: 0.99)
    }

    func testGermanVerbFormsAreReadAsTheirVerbs() throws {
        check(try auditVerbForms(GermanProfile(), carrier: Self.germanCarrier, fullSample: 15_000), minimum: 0.98)
    }
}
