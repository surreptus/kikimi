import XCTest
@testable import LangCore

/// Mistakes found on real Spanish clips. Each sentence is a subtitle line from one.
final class SpanishTokenizerTests: XCTestCase {
    private let profile = SpanishProfile()

    private func content(_ text: String) -> [Token] { profile.contentWords(in: text) }
    private func token(_ surface: String, in text: String) throws -> Token {
        try XCTUnwrap(profile.tokenizer.tokens(in: text).first { $0.surface == surface }, "\(surface) not found")
    }

    func testAnArticleIsNotAVerb() throws {
        let text = "unos tomates, unas cebollas y lo que no sé es si quedan patatas."
        XCTAssertEqual(try token("unas", in: text).pos, .other)
        XCTAssertFalse(content(text).contains { $0.surface == "unas" })
        XCTAssertTrue(content(text).contains { $0.lemma == "cebolla" })
    }

    func testACutOffWordIsNotAContentWord() throws {
        let text = "Es que por haber, no hab- Es que no había nada,"
        XCTAssertTrue(try token("hab", in: text).isCutOff)
        XCTAssertFalse(content(text).contains { $0.surface == "hab" })
        XCTAssertFalse(content("la noche anterior mirar el depósito y ver si me quedaba o no pues para-").contains { $0.surface == "para" })
        // A word joined to another by a hyphen is whole.
        XCTAssertFalse(try token("hispano", in: "Es un país hispano-americano.").isCutOff)
        XCTAssertTrue(content("Es un país hispano-americano.").contains { $0.surface == "hispano" })
    }

    func testAVerbAfterAnotherVerbIsNotANoun() throws {
        let verb = try token("cargo", in: "y dije: bueno vale, pues me pongo y cargo ahí el coche.")
        XCTAssertEqual(verb.lemma, "cargar")
        XCTAssertEqual(verb.pos, .verb)
        XCTAssertEqual(try token("cargo", in: "Yo cargo el coche.").lemma, "cargar")
        // The noun stays a noun.
        XCTAssertEqual(try token("cargo", in: "Tiene un cargo importante en la empresa.").pos, .noun)
        XCTAssertEqual(try token("trabajo", in: "Tengo mucho trabajo y poco tiempo.").pos, .noun)
    }

    func testAParticipleAfterHaberIsTheVerb() throws {
        let text = "Pero hoy como tenía una entrevista de trabajo he salido perfecta."
        let salido = try token("salido", in: text)
        XCTAssertEqual(salido.lemma, "salir")
        XCTAssertEqual(salido.pos, .verb)
        XCTAssertEqual(Set(content(text).filter { $0.surface == "salido" }.map(\.lemma)), ["salir"])
    }

    func testTheAccentIsRestored() throws {
        XCTAssertEqual(try token("tia", in: "But tia, no te vas a creer lo que me ha pasado esta mañana.").lemma, "tía")
        XCTAssertEqual(try token("tía", in: "Mi tía vive en Madrid.").lemma, "tía")
    }

    func testOkayIsAnInterjectionOnlyOnItsOwn() throws {
        XCTAssertEqual(try token("vale", in: "Ya me dices ¿vale?").pos, .other)
        XCTAssertFalse(content("Ya me dices ¿vale?").contains { $0.surface == "vale" })
        XCTAssertEqual(try token("Vale", in: "Vale, nos vemos luego.").pos, .other)
        // The verb is a verb.
        XCTAssertEqual(try token("vale", in: "Este libro vale mucho dinero.").lemma, "valer")
        XCTAssertEqual(try token("vale", in: "¿Cuánto vale?").lemma, "valer")
    }

    func testHeyIsAnInterjection() throws {
        let text = "Ey, ¿qué pasa? ¿Cómo andamos? Que hace mazo que no nos vemos,"
        XCTAssertEqual(try token("Ey", in: text).pos, .other)
        XCTAssertFalse(content(text).contains { $0.surface == "Ey" })
    }

    func testAKnownNameInsideASentenceIsNotAWordToLearn() throws {
        let text = "Vivo en Madrid con mi hermana María."
        XCTAssertFalse(content(text).contains { $0.surface == "Madrid" || $0.surface == "María" })
        XCTAssertTrue(content(text).contains { $0.lemma == "hermana" })
    }
}
