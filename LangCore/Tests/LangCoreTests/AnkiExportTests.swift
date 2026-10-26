import GRDB
import XCTest
@testable import LangCore

final class AnkiExportTests: XCTestCase {
    private func word(_ lemma: String = "casa", language: String = "es") -> Word {
        Word(id: 1, language: language, lemma: lemma, pos: .noun, status: .learning, stage: .stage2)
    }

    private func example(_ text: String, surface: String) throws -> ExampleLine {
        try ExampleLine(row: Row(["subtitle_id": 7, "surface": surface, "text": text, "start_time": 1.0, "end_time": 2.0,
                                  "video_id": 1, "video_title": "Un día", "media_path": "h/video.mov"]))
    }

    func testACardHasTheWordMeaningAndASentenceWithTheWordInBold() throws {
        let card = AnkiExport.card(
            word: word(), reading: nil, gloss: "1. (noun) house\n2. (noun) home",
            example: try example("La casa es grande.", surface: "casa"), audioFile: "kikimi-casa-7.m4a")
        XCTAssertEqual(card.guid, "kikimi:es:casa:noun")
        XCTAssertEqual(card.front, "casa")
        XCTAssertEqual(card.back, "1. (noun) house<br>2. (noun) home<br><br><i>La <b>casa</b> es grande.</i><br><small>Un día</small><br>[sound:kikimi-casa-7.m4a]")
        XCTAssertEqual(card.tags, ["kikimi", "kikimi_es"])
    }

    func testTheReadingComesFirstOnTheBackAndIsLeftOutWhenItIsTheWord() throws {
        let withReading = AnkiExport.card(word: word("秋", language: "ja"), reading: "あき", gloss: "autumn", example: nil, audioFile: nil)
        XCTAssertEqual(withReading.back, "あき<br>autumn")
        let same = AnkiExport.card(word: word("いえ", language: "ja"), reading: "いえ", gloss: "house", example: nil, audioFile: nil)
        XCTAssertEqual(same.back, "house")
    }

    func testMarkupInTheTextIsEscapedAndAMissingMeaningStillMakesACard() throws {
        let card = AnkiExport.card(word: word("a<b"), reading: nil, gloss: nil,
                                   example: try example("Tom & Jerry <3", surface: "Tom"), audioFile: nil)
        XCTAssertEqual(card.front, "a&lt;b")
        XCTAssertEqual(card.back, "<br><i><b>Tom</b> &amp; Jerry &lt;3</i><br><small>Un día</small>")
        let bare = AnkiExport.card(word: word(), reading: nil, gloss: nil, example: nil, audioFile: nil)
        XCTAssertEqual(bare.back, "")
    }

    func testTheFileHasTheHeaderLinesAndOneTabSeparatedRowPerCard() {
        let cards = [
            AnkiCard(guid: "g1", front: "casa", back: "house\nwith a\ttab", tags: ["kikimi", "kikimi_es"]),
            AnkiCard(guid: "g2", front: "perro", back: "dog", tags: ["kikimi"]),
        ]
        let text = AnkiExport.importFile(cards: cards, deck: "Kikimi Spanish")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(Array(lines.prefix(6)), ["#separator:tab", "#html:true", "#guid column:1", "#notetype:Basic",
                                                "#deck:Kikimi Spanish", "#tags column:4"])
        XCTAssertEqual(lines[6], "g1\tcasa\thouse<br>with a tab\tkikimi kikimi_es", "no raw tab or line break inside a field")
        XCTAssertEqual(lines[7], "g2\tperro\tdog\tkikimi")
        XCTAssertEqual(lines[6].filter { $0 == "\t" }.count, 3, "four columns")
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testTheLearningWordsComeBackMostSeenFirstForOneLanguage() async throws {
        let db = try LangDatabase()
        try await db.writer.write { d in
            var v = Video(language: "es", title: "v", contentHash: "h", videoPath: "h/v.mov", duration: 9); try v.insert(d)
            func add(_ lemma: String, _ status: WordStatus, lines: Int, language: String = "es") throws {
                var w = Word(language: language, lemma: lemma, pos: .noun, status: status); try w.insert(d)
                for i in 0..<lines {
                    var s = Subtitle(videoId: v.id!, idx: Int.random(in: 0..<1_000_000), startTime: Double(i), endTime: Double(i) + 1, text: "x"); try s.insert(d)
                    var o = Occurrence(wordId: w.id!, subtitleId: s.id!, surface: lemma); try o.insert(d)
                }
            }
            try add("poco", .learning, lines: 1)
            try add("mucho", .learning, lines: 3)
            try add("nada", .known, lines: 5)
            try add("nuevo", .new, lines: 2)
            try add("ja", .learning, lines: 1, language: "ja")
        }
        let ids = try await db.learningWordIDs(language: "es")
        let lemmas = try await db.writer.read { db in try ids.map { try Word.fetchOne(db, key: $0)!.lemma } }
        XCTAssertEqual(lemmas, ["mucho", "poco"])
    }

    func testExportingWritesTheFileAndTheSentenceAudio() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "anki-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "clip.mov")
        try await FixtureVideo.make(at: source, seconds: 6)
        let env = try LangEnvironment(
            root: dir.appending(path: "container"), defaults: UserDefaults(suiteName: "anki-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([TranscriptSegment(start: 1, end: 2, text: "La casa es grande.")])))
        _ = try await env.pipeline.importVideo(from: source, profile: SpanishProfile())
        let casa = try await env.database.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        try await env.database.startLearning(wordID: casa)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let learning = try await env.database.learningWordIDs(language: "es")
        XCTAssertEqual(learning, [casa])
        let result = try await env.exportAnki(wordIDs: learning, language: "es", includeAudio: true, into: out)
        XCTAssertEqual(result.cards, 1)
        XCTAssertEqual(result.audioFiles, 1)
        let text = try String(contentsOf: result.file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("#separator:tab"))
        XCTAssertTrue(text.contains("#deck:Kikimi Spanish"))
        XCTAssertTrue(text.contains("kikimi:es:casa:noun\tcasa\t"))
        let media = try FileManager.default.contentsOfDirectory(atPath: result.mediaFolder!.path)
        XCTAssertEqual(media.count, 1)
        XCTAssertTrue(text.contains("[sound:\(media[0])]"), "the card points at the clip that was written")

        let textOnly = try await env.exportAnki(wordIDs: learning, language: "es", includeAudio: false, into: out)
        XCTAssertEqual(textOnly.audioFiles, 0)
        XCTAssertNil(textOnly.mediaFolder)
        XCTAssertNotEqual(textOnly.file, result.file, "an earlier export is never overwritten")
        XCTAssertFalse(try String(contentsOf: textOnly.file, encoding: .utf8).contains("[sound:"))
    }
}
