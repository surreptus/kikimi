import XCTest
@testable import LangCore

/// The pure parts of the tokenizer audit, on made-up tokens.
final class TokenAuditTests: XCTestCase {
    private func token(_ surface: String, _ lemma: String? = nil, _ pos: PartOfSpeech = .noun, cutOff: Bool = false,
                       content: Bool = true, entry: Bool? = true, in sentence: String = "una frase") -> AuditToken {
        AuditToken(surface: surface, lemma: lemma ?? surface, pos: pos, isCutOff: cutOff, isContent: content, hasEntry: entry,
                   sentence: sentence)
    }

    private func report(_ tokens: [AuditToken], endings: [String] = ["ar", "er", "ir"]) -> AuditReport {
        TokenAudit.report(language: "es", lines: 3, tokens: tokens, infinitiveEndings: endings)
    }

    func testMissingLemmasAreRankedByCountThenName() {
        let r = report([token("zzz", entry: false), token("bbb", entry: false), token("aaa", entry: false),
                        token("bbb", entry: false), token("casa")])
        XCTAssertEqual(r.suspects(in: .missingEntry).map(\.key), ["bbb (noun)", "aaa (noun)", "zzz (noun)"])
        XCTAssertEqual(r.suspects(in: .missingEntry).first?.count, 2)
        XCTAssertEqual(r.noEntryWords, 4)
        XCTAssertEqual(r.noEntryLemmas, 3)
        XCTAssertEqual(r.contentWords, 5)
    }

    func testOnlyContentWordsAreCountedAndAnUncheckedDictionaryIsSaid() {
        let r = report([token("xyz", entry: false), token("de", content: false, entry: nil)])
        XCTAssertEqual(r.noEntryWords, 1, "a token outside the content words is not counted")
        let unchecked = report([token("casa", entry: nil)])
        XCTAssertNil(unchecked.noEntryWords)
        XCTAssertTrue(unchecked.suspects(in: .missingEntry).isEmpty)
        XCTAssertTrue(TokenAudit.render(unchecked).contains("not checked"))
    }

    func testSameSpellingWithTwoReadingsIsGroupedWithItsRarestExample() {
        let r = report([
            token("Salido", "salido", .noun, in: "el salido"),
            token("salido", "salir", .verb, in: "he salido ya"),
            token("salido", "salir", .verb, in: "había salido"),
            token("casa", "casa"),
        ])
        let found = r.suspects(in: .mixedTags)
        XCTAssertEqual(found.map(\.key), ["salido"])
        XCTAssertEqual(found[0].count, 3)
        XCTAssertEqual(found[0].detail, "verb salir ×2, noun salido ×1")
        XCTAssertEqual(found[0].example, "el salido")
    }

    func testCutOffTokensAndLookalikes() {
        let r = report([
            token("hab", cutOff: true, content: false, entry: nil, in: "no hab- es"),
            token("pero", in: "pero… sí"),  // has an entry: a real word
            token("fu", entry: false, in: "el fu- dijo"),
            token("xx", entry: false, in: "dijo xx"),
        ])
        XCTAssertEqual(r.suspects(in: .cutOff).map(\.key), ["hab"])
        let looks = r.suspects(in: .looksCutOff)
        XCTAssertEqual(Set(looks.map(\.key)), ["fu", "xx"])
        XCTAssertEqual(looks.first { $0.key == "fu" }?.detail, "followed by a dash or ellipsis")
    }

    func testTrailingMarkNeedsNoLetterAfter() {
        XCTAssertTrue(TokenAudit.endsInTrailingMark("hab", in: "no hab- es"))
        XCTAssertTrue(TokenAudit.endsInTrailingMark("hab", in: "no hab..."))
        XCTAssertTrue(TokenAudit.endsInTrailingMark("Hab", in: "no hab—"))
        XCTAssertFalse(TokenAudit.endsInTrailingMark("hab", in: "no hab-lo bien"), "a hyphenated word is whole")
        XCTAssertFalse(TokenAudit.endsInTrailingMark("hab", in: "la hab es"))
        XCTAssertFalse(TokenAudit.endsInTrailingMark("ab", in: "no hab-"), "inside another word")
    }

    func testVerbWhoseLemmaIsItsSpellingMustEndLikeAnInfinitive() {
        let r = report([
            token("salido", "salido", .verb), token("salido", "salido", .verb), token("comer", "comer", .verb),
            token("irse", "irse", .verb), token("cuenta", "cuenta", .noun), token("canto", "cantar", .verb),
        ])
        XCTAssertEqual(r.suspects(in: .verbNotInfinitive).map(\.key), ["salido"])
        XCTAssertEqual(r.suspects(in: .verbNotInfinitive).first?.count, 2)
        XCTAssertTrue(report([token("salido", "salido", .verb)], endings: []).suspects(in: .verbNotInfinitive).isEmpty,
                      "a language with no endings has no such check")
    }

    func testBaselineDiffFindsNewAndGoneSuspectsWhateverTheirCount() {
        let old = report([token("aaa", entry: false), token("bbb", entry: false)])
        let now = report([token("bbb", entry: false), token("bbb", entry: false), token("ccc", entry: false)])
        let diff = TokenAudit.diff(now, against: old)
        XCTAssertEqual(diff.new.map(\.key), ["ccc (noun)"])
        XCTAssertEqual(diff.gone.map(\.key), ["aaa (noun)"])
        XCTAssertTrue(TokenAudit.diff(now, against: now).isEmpty)
        XCTAssertTrue(TokenAudit.render(TokenAudit.diff(now, against: now)).contains("no change"))
    }

    func testReportSurvivesTheBaselineFileAndReadsStably() throws {
        let r = report([token("aaa", entry: false, in: "dijo aaa"), token("a", "a", .verb, entry: false)])
        let data = try TokenAudit.encode(r)
        XCTAssertEqual(try TokenAudit.decode(data), r)
        XCTAssertEqual(try TokenAudit.encode(r), data, "the same report gives the same bytes")
        let text = TokenAudit.render(r)
        XCTAssertTrue(text.contains("Lemma not in the dictionary (2)"))
        XCTAssertTrue(text.contains("aaa (noun)"))
        XCTAssertTrue(text.contains("\u{201C}dijo aaa\u{201D}"))
    }
}
