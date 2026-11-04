import GRDB
import XCTest
@testable import LangCore

final class SubtitleParserTests: XCTestCase {
    func testSubRipCuesWithNumbersCommasAndSeveralLines() {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        La casa es grande.

        2
        00:00:04,250 --> 00:00:06,000
        Hola,
        ¿cómo estás?
        """
        XCTAssertEqual(SubtitleParser.parse(srt), [
            TranscriptSegment(start: 1, end: 3.5, text: "La casa es grande."),
            TranscriptSegment(start: 4.25, end: 6, text: "Hola, ¿cómo estás?"),
        ])
    }

    func testWebVTTWithHeaderIdsSettingsNotesAndShortTimes() {
        let vtt = """
        WEBVTT - a file

        NOTE this is a comment
        that goes on

        intro
        00:01.500 --> 00:03.000 align:start position:10%
        <v Mia>Buenos <i>días</i>.

        01:00:02.000 --> 01:00:04.000
        Una hora después.
        """
        let cues = SubtitleParser.parse(vtt)
        XCTAssertEqual(cues.map(\.text), ["Buenos días.", "Una hora después."])
        XCTAssertEqual(cues[0].start, 1.5)
        XCTAssertEqual(cues[1].start, 3602, "hours are read")
    }

    func testMarkupEntitiesAndStyleCodesAreRemoved() {
        let srt = "1\n00:00:00,000 --> 00:00:02,000\n{\\an8}<font color=\"#fff\">Tom &amp; Jerry</font> &lt;3\n"
        XCTAssertEqual(SubtitleParser.parse(srt).map(\.text), ["Tom & Jerry <3"])
    }

    func testWindowsLineEndingsAndMissingBlankLinesBetweenCues() {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,000\r\nUno\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nDos\r\n"
        XCTAssertEqual(SubtitleParser.parse(srt).map(\.text), ["Uno", "Dos"], "the next cue's number ends the first")
    }

    func testCuesAreSortedAndEmptyOrBackwardsOnesAreDropped() {
        let srt = """
        1
        00:00:05,000 --> 00:00:06,000
        Dos

        2
        00:00:01,000 --> 00:00:02,000
        Uno

        3
        00:00:07,000 --> 00:00:08,000
        <i></i>

        4
        00:00:09,000 --> 00:00:08,000
        Al revés
        """
        XCTAssertEqual(SubtitleParser.parse(srt).map(\.text), ["Uno", "Dos"])
    }

    func testJapaneseLinesAreJoinedWithoutASpace() {
        let srt = "1\n00:00:00,000 --> 00:00:03,000\n今日は\n横浜に来ました。\n"
        XCTAssertEqual(SubtitleParser.parse(srt, lineJoiner: JapaneseProfile().dictationSeparator).map(\.text), ["今日は横浜に来ました。"])
        XCTAssertEqual(SubtitleParser.parse(srt).map(\.text), ["今日は 横浜に来ました。"])
    }

    func testEncodingsAreRead() {
        let text = "1\n00:00:00,000 --> 00:00:02,000\nCafé\n"
        XCTAssertEqual(SubtitleParser.parse(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))?.first?.text, "Café", "UTF-8 with a mark")
        XCTAssertEqual(SubtitleParser.parse(text.data(using: .utf16)!)?.first?.text, "Café", "UTF-16")
        XCTAssertEqual(SubtitleParser.parse(text.data(using: .isoLatin1)!)?.first?.text, "Café", "Western")
        XCTAssertEqual(SubtitleParser.parse("1\n00:00:00,000 --> 00:00:02,000\nこんにちは\n".data(using: .shiftJIS)!)?.first?.text, "こんにちは", "Shift JIS")
    }

    func testAFileWithNoCuesGivesNone() {
        XCTAssertEqual(SubtitleParser.parse("WEBVTT\n\nNOTE nothing here\n"), [])
        XCTAssertEqual(SubtitleParser.parse(""), [])
    }

    func testTextInOtherLanguagesIsRecognised() {
        XCTAssertEqual(SubtitleLanguage.guess("La casa es muy grande y mi hermana vive en otra ciudad.")?.code, "es")
        XCTAssertEqual(SubtitleLanguage.guess("The house is very big and my sister lives in another city.")?.code, "en")
        XCTAssertEqual(SubtitleLanguage.guess("今日は横浜に来ました。とても楽しかったです。")?.code, "ja")
    }
}

final class SubtitlePairingTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(filePath: "/tmp/" + name) }

    func testSubtitlesPairByNameWithOrWithoutALanguageTag() {
        let result = SubtitlePairing.pair([url("A.mp4"), url("A.srt"), url("B.mov"), url("b.es.vtt"), url("C.mp4")])
        XCTAssertEqual(result.items.map(\.subtitles?.lastPathComponent), ["A.srt", "b.es.vtt", nil])
        XCTAssertEqual(result.items.map(\.video.lastPathComponent), ["A.mp4", "B.mov", "C.mp4"])
        XCTAssertEqual(result.unmatched, [])
    }

    func testTheSubtitleInTheChosenLanguageIsPreferred() {
        let urls = [url("film.mp4"), url("film.en.srt"), url("film.es.srt")]
        XCTAssertEqual(SubtitlePairing.pair(urls, language: "es").items[0].subtitles?.lastPathComponent, "film.es.srt")
        XCTAssertEqual(SubtitlePairing.pair(urls, language: "en").items[0].subtitles?.lastPathComponent, "film.en.srt")
        XCTAssertEqual(SubtitlePairing.pair(urls, language: "ja").items[0].subtitles?.lastPathComponent, "film.en.srt", "the first, if none match")
        XCTAssertEqual(SubtitlePairing.pair(urls, language: "es").unmatched.map(\.lastPathComponent), ["film.en.srt"])
    }

    func testALoneSubtitleBelongsToALoneVideoWhateverItsName() {
        let one = SubtitlePairing.pair([url("movie.mp4"), url("subs-final.srt")])
        XCTAssertEqual(one.items[0].subtitles?.lastPathComponent, "subs-final.srt")
        let two = SubtitlePairing.pair([url("a.mp4"), url("b.mp4"), url("whatever.srt")])
        XCTAssertEqual(two.items.map(\.subtitles), [nil, nil], "with two videos the name has to match")
        XCTAssertEqual(two.unmatched.map(\.lastPathComponent), ["whatever.srt"])
    }

    func testASubtitleAloneHasNoVideo() {
        let result = SubtitlePairing.pair([url("only.srt")])
        XCTAssertEqual(result.items, [])
        XCTAssertEqual(result.unmatched.map(\.lastPathComponent), ["only.srt"])
    }
}

final class SubtitleImportTests: XCTestCase {
    let spanish = SpanishProfile()

    private func write(_ text: String, named name: String, beside h: ImportHarness) throws -> URL {
        let url = h.original.deletingLastPathComponent().appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let goodSRT = """
    1
    00:00:00,000 --> 00:00:01,000
    La casa es grande.

    2
    00:00:01,000 --> 00:00:02,000
    [Música]

    3
    00:00:01,000 --> 00:00:02,000
    Corremos rápidamente a la casa.
    """

    func testSubtitlesAreUsedInsteadOfTranscribing() async throws {
        let h = try await ImportHarness()
        let srt = try write(goodSRT, named: "clip.srt", beside: h)
        // A transcriber that fails proves the speech model is not asked.
        let pipeline = h.pipeline(transcriber: StubTranscriber(result: .failure(Failure()), detectionFails: true))
        let stages = Box<[ImportStage]>([])
        let video = try await pipeline.importVideo(from: h.original, subtitles: srt, profile: spanish, progress: { p in
            if stages.value.last != p.stage { stages.value.append(p.stage) }
        })
        try h.assertOriginalUntouched()
        XCTAssertFalse(stages.value.contains(.transcribing) || stages.value.contains(.detectingLanguage), "\(stages.value)")
        try await h.database.writer.read { db in
            XCTAssertEqual(try Subtitle.filter(Column("video_id") == video.id!).order(Column("idx")).fetchAll(db).map(\.text),
                           ["La casa es grande.", "Corremos rápidamente a la casa."], "the sound description is dropped")
            XCTAssertNotNil(try Word.filter(Column("lemma") == "casa").fetchOne(db), "its words are found as usual")
        }
    }

    func testSubtitlesThatAreNotUsableStopTheImportAndChangeNothing() async throws {
        let h = try await ImportHarness()
        let none = try write("WEBVTT\n", named: "none.vtt", beside: h)
        let late = try write("1\n00:01:00,000 --> 00:01:02,000\nLa casa es grande.\n", named: "late.srt", beside: h)
        let missing = h.original.deletingLastPathComponent().appending(path: "missing.srt")
        let english = try write("1\n00:00:00,000 --> 00:00:02,000\nThe house is very big and my sister lives in another city.\n", named: "en.srt", beside: h)
        let french = try write("1\n00:00:00,000 --> 00:00:02,000\nLa maison est très grande et ma soeur habite dans une autre ville.\n", named: "fr.srt", beside: h)
        let pipeline = h.pipeline()

        func problem(_ file: URL) async -> String {
            do { _ = try await pipeline.importVideo(from: h.original, subtitles: file, profile: spanish); return "imported" }
            catch ImportError.subtitlesUnusable(let p) { return "\(p)" }
            catch ImportError.languageMismatch(let detected, _, _) { return "mismatch \(detected)" }
            catch { return "\(error)" }
        }
        let none_ = await problem(none), late_ = await problem(late), missing_ = await problem(missing)
        let english_ = await problem(english), french_ = await problem(french)
        XCTAssertEqual(none_, "noSubtitles")
        XCTAssertEqual(late_, "outsideVideo")
        XCTAssertEqual(missing_, "unreadable")
        XCTAssertTrue(english_.hasPrefix("otherLanguage"), english_)
        XCTAssertEqual(french_, "mismatch fr", "a language Kikimi supports is offered as a switch, as for audio")
        try h.assertOriginalUntouched()
        try await h.database.writer.read { db in XCTAssertEqual(try Video.fetchCount(db), 0) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.container.appending(path: "Staging").path), [])
    }

    func testTheLanguageCheckCanBeSkippedForSubtitlesToo() async throws {
        let h = try await ImportHarness()
        let french = try write("1\n00:00:00,000 --> 00:00:02,000\nLa maison est très grande et ma soeur habite dans une autre ville.\n", named: "fr.srt", beside: h)
        let video = try await h.pipeline().importVideo(from: h.original, subtitles: french, profile: spanish, checkLanguage: false)
        XCTAssertEqual(video.language, "es")
    }

    func testTheStepsOfAnImportWithSubtitlesLeaveOutTranscribing() {
        XCTAssertFalse(ImportStage.steps(checkingLanguage: false, transcribing: false).contains(.transcribing))
        XCTAssertEqual(ImportStage.steps(checkingLanguage: true, compressing: true, transcribing: true).count, 7)
        XCTAssertEqual(ImportStage.steps(checkingLanguage: false, compressing: true, transcribing: false).count, 5)
    }
}

/// A value several tasks can write to, for collecting what a progress callback reports.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
