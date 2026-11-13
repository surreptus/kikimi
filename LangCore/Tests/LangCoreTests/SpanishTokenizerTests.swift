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

    func testACutOffParaIsThePrepositionNotParar() throws {
        let text = "la noche anterior mirar el depósito y ver si me quedaba o no pues para-"
        let para = try token("para", in: text)
        XCTAssertEqual(para.lemma, "para")
        XCTAssertEqual(para.pos, .other)
        XCTAssertTrue(para.isCutOff)
        // The preposition stays one, before an infinitive, a noun phrase and "que".
        XCTAssertEqual(try token("para", in: "había pensado en comprar dos barras de pan para el desayuno,").lemma, "para")
        XCTAssertEqual(try token("para", in: "Es para comer.").lemma, "para")
        XCTAssertEqual(try token("para", in: "Lo hago para que vengas.").lemma, "para")
    }

    func testParaTheTaggerReadsAsAVerbStaysTheVerb() throws {
        // The rule only moves a word the tagger did not call a verb. Here the tagger says verb, and it stays.
        let no = try token("para", in: "No para de hablar.")
        XCTAssertEqual(no.lemma, "parar")
        // The tagger reads "el tren para en la estación" as the preposition. The rule does not change that.
        XCTAssertEqual(try token("para", in: "El tren para en la estación.").pos, .other)
    }

    func testSeWithAnAccentIsTheVerbSaberEveryTime() throws {
        for text in ["unos tomates, unas cebollas y lo que no sé es si quedan patatas.", "Es que soy gilipollas. No sé cómo no se me ocurrió",
                     "porque sé que tú siempre estás más liadilla,"] {
            let sé = try token("sé", in: text)
            XCTAssertEqual(sé.lemma, "saber")
            XCTAssertEqual(sé.pos, .verb)
            XCTAssertTrue(content(text).contains { $0.lemma == "saber" })
        }
        // The pronoun without an accent is not a verb.
        let se = try token("se", in: "Es que no se me ocurrió.")
        XCTAssertEqual(se.pos, .other)
        XCTAssertNotEqual(se.lemma, "saber")
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

    func testEachChosenConjunctionIsOneInARealSentence() throws {
        let lines: [(String, String)] = [
            ("porque", "No voy porque estoy cansado."), ("Pero", "Pero no puedo ir."), ("aunque", "Voy aunque llueva."),
            ("mientras", "Canto mientras cocino."), ("sino", "No es rojo sino azul."), ("Pues", "Pues, vamos."),
            ("Cuando", "Cuando llegues, llámame."),
        ]
        for (surface, text) in lines {
            let word = try token(surface, in: text)
            XCTAssertEqual(word.pos, .conjunction, text)
            XCTAssertEqual(word.lemma, surface.lowercased(), text)
            XCTAssertTrue(content(text).contains { $0.surface == surface }, "it is a content word of Spanish: \(text)")
        }
    }

    func testTheTaggerCallingAChosenConjunctionANounDoesNotChangeIt() throws {
        // The tagger reads "Pues." and "Sino" on their own as nouns.
        XCTAssertEqual(try token("Pues", in: "Pues.").pos, .conjunction)
        XCTAssertEqual(try token("Sino", in: "Sino").pos, .conjunction)
    }

    func testComoStaysTheVerbAndOtherConjunctionsStayOther() throws {
        XCTAssertEqual(try token("Como", in: "Como pan.").pos, .adverb, "the tagger's own answer, not a conjunction")
        XCTAssertEqual(try token("pan", in: "Como pan.").pos, .verb)
        let text = "Dime que y yo vamos, y si quieres, o no."
        for surface in ["que", "y", "si", "o"] { XCTAssertNotEqual(try token(surface, in: text).pos, .conjunction, surface) }
        XCTAssertEqual(try token("que", in: text).pos, .other)
        XCTAssertEqual(try token("y", in: text).pos, .other)
        XCTAssertFalse(content(text).contains { $0.surface == "que" || $0.surface == "y" })
    }

    func testTheQuestionsAreNotConjunctions() throws {
        XCTAssertNotEqual(try token("cuándo", in: "No sé cuándo llegó.").pos, .conjunction)
        XCTAssertNotEqual(try token("qué", in: "Dime por qué.").pos, .conjunction)
        XCTAssertNotEqual(try token("porqué", in: "El porqué de todo.").pos, .conjunction)
    }

    func testOtherLanguagesLeaveConjunctionsOut() {
        for profile in LanguageProfiles.all where profile.code != "es" { XCTAssertFalse(profile.contentPOS.contains(.conjunction), profile.code) }
        XCTAssertTrue(profile.contentPOS.contains(.conjunction))
    }
}
