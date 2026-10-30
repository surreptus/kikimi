import XCTest
@testable import LangCore

final class ProfileTests: XCTestCase {
    func testRegistry() {
        XCTAssertEqual(LanguageProfiles.all.map(\.code), ["es", "fr", "de", "ja"])
        XCTAssertEqual(LanguageProfiles.profile(for: "ja")?.defaultModel, "openai_whisper-large-v3")
        XCTAssertEqual(LanguageProfiles.profile(for: "es")?.defaultModel, "openai_whisper-medium")
        XCTAssertNil(LanguageProfiles.profile(for: "xx"))
    }

    func testFrenchContentWords() {
        let words = FrenchProfile().contentWords(in: "Nous avons mangé au restaurant avec les enfants hier soir.")
        let lemmas = Set(words.map(\.lemma))
        XCTAssertTrue(lemmas.isSuperset(of: ["avoir", "manger", "enfant", "soir"]), "\(lemmas)")
        XCTAssertFalse(lemmas.contains("les"))
        XCTAssertFalse(lemmas.contains("avec"))
    }

    func testGermanContentWords() {
        let words = GermanProfile().contentWords(in: "Wir haben im Garten gearbeitet. Du musst gehen, ich kann es machen.")
        let lemmas = Set(words.map(\.lemma))
        XCTAssertTrue(lemmas.isSuperset(of: ["haben", "garten", "arbeiten", "gehen", "machen"]), "\(lemmas)")
        // The tagger answers "muessen" and "koennen" for these; the profile corrects them.
        XCTAssertTrue(lemmas.isSuperset(of: ["müssen", "können"]), "\(lemmas)")
        XCTAssertFalse(lemmas.contains("der"))
    }

    /// The bundled dictionaries must find the words the tokenizer produces, or learners see empty word panels.
    func testGermanAndFrenchLemmasAreInTheirDictionaries() async throws {
        let profiles: [any LanguageProfile] = [FrenchProfile(), GermanProfile()]
        let store = try DictionaryStore.bundled(for: profiles)
        let sentences = [
            "de": "Ich rufe dich morgen an, wenn ich nach Hause komme. Kannst du bitte das Fenster aufmachen? Die Kinder sind schon eingeschlafen.",
            "fr": "Je ne sais pas ce qu'il veut vraiment faire demain. Elle s'est levée tôt parce qu'elle devait prendre le train. Les voisins ont acheté une voiture rouge.",
        ]
        for profile in profiles {
            let lemmas = Set(profile.contentWords(in: sentences[profile.code]!).map(\.lemma))
            for lemma in lemmas {
                let found = try await store.lookup(language: profile.code, term: lemma, limit: 1)
                XCTAssertFalse(found.isEmpty, "\(profile.code): no entry for \(lemma)")
            }
        }
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
