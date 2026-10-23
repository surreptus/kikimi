import XCTest
@testable import LangCore

final class ProfileTests: XCTestCase {
    func testRegistry() {
        XCTAssertEqual(LanguageProfiles.all.map(\.code), ["es", "ja"])
        XCTAssertEqual(LanguageProfiles.profile(for: "ja")?.defaultModel, "openai_whisper-large-v3")
        XCTAssertEqual(LanguageProfiles.profile(for: "es")?.defaultModel, "openai_whisper-medium")
        XCTAssertNil(LanguageProfiles.profile(for: "xx"))
    }

    func testCodesAreUnique() {
        let codes = LanguageProfiles.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testSpanishContentWords() {
        let words = SpanishProfile().contentWords(in: "La casa grande es muy bonita y corremos rápidamente.")
        let lemmas = Set(words.map(\.lemma))
        print("es lemmas:", words.map { "\($0.surface)->\($0.lemma)/\($0.pos)" })
        XCTAssertTrue(lemmas.contains("casa"))
        XCTAssertFalse(lemmas.contains("la"))
        XCTAssertFalse(lemmas.contains("y"))
        XCTAssertTrue(words.allSatisfy { SpanishProfile().contentPOS.contains($0.pos) })
    }
}
