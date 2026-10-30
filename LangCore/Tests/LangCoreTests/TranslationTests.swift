import GRDB
import XCTest
@testable import LangCore

/// A translator that records what it was asked and "translates" by prefixing; lines with "FAIL" in them come back nil.
private final class StubTranslator: LineTranslator, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [[String]] = []
    var status = TranslationAvailability.ready
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return log }
    func availability() async -> TranslationAvailability { status }
    func translate(_ lines: [String]) async throws -> [String?] {
        lock.lock(); log.append(lines); lock.unlock()
        return lines.map { $0.contains("FAIL") ? nil : "T: " + $0 }
    }
}

final class TranslationTests: XCTestCase {
    private let spanish = SpanishProfile()

    private func library(_ texts: [String]) async throws -> (db: LangDatabase, lines: [Subtitle]) {
        let db = try LangDatabase()
        let video = try await db.saveImport(
            video: Video(language: "es", title: "v", contentHash: "h", videoPath: "h/video.mov", duration: 60),
            subtitles: texts.enumerated().map { (TranscriptSegment(start: Double($0.offset), end: Double($0.offset) + 1, text: $0.element), []) })
        return (db, try await db.subtitles(videoID: video.id!))
    }

    func testOnlyLinesWithoutATranslationAreAskedForAndTheResultsAreKept() async throws {
        let (db, lines) = try await library(["Hola", "Buenos días", "Gracias"])
        let stub = StubTranslator()
        let service = TranslationService(database: db, translator: stub, target: "en")

        let first = try await service.translate([lines[0], lines[1]])
        XCTAssertEqual(first[lines[0].id!], "T: Hola")
        XCTAssertEqual(stub.calls, [["Hola", "Buenos días"]])

        let second = try await service.translate(lines)       // two are already kept
        XCTAssertEqual(second.count, 3, "all three come back")
        XCTAssertEqual(stub.calls.last, ["Gracias"], "only the new one was translated")
        let stored = try await service.stored(videoID: lines[0].videoId)
        XCTAssertEqual(stored.count, 3)

        let again = try await service.translate(lines)
        XCTAssertEqual(again.count, 3)
        XCTAssertEqual(stub.calls.count, 2, "nothing left to ask for, so the translator isn't called")
    }

    func testTranslationsAreKeptPerLanguage() async throws {
        let (db, lines) = try await library(["Hola"])
        _ = try await TranslationService(database: db, translator: StubTranslator(), target: "en").translate(lines)
        let french = try await db.translations(videoID: lines[0].videoId, target: "fr")
        XCTAssertTrue(french.isEmpty, "an English translation isn't a French one")
    }

    func testLinesWithNoWordsAreNeverSentAndFailedOnesAreRetriedLater() async throws {
        let (db, lines) = try await library(["♪", "FAIL once", "Hola", "   "])
        let stub = StubTranslator()
        let service = TranslationService(database: db, translator: stub, target: "en")
        let result = try await service.translate(lines)
        XCTAssertEqual(stub.calls, [["FAIL once", "Hola"]], "the music note and the blank line never reach the translator")
        XCTAssertEqual(Set(result.values), ["T: Hola"], "the failed line has none")
        _ = try await service.translate(lines)
        XCTAssertEqual(stub.calls.last, ["FAIL once"], "only the failed line is asked for again")
        XCTAssertEqual(stub.calls.count, 2)
    }

    func testBigRequestsGoInBatches() async throws {
        let (db, lines) = try await library((0..<5).map { "Línea \($0)" })
        let stub = StubTranslator()
        _ = try await TranslationService(database: db, translator: stub, target: "en", batchSize: 2).translate(lines + [lines[0]])
        XCTAssertEqual(stub.calls.map(\.count), [2, 2, 1], "five lines, in batches of two; the repeat is translated once")
    }

    func testEditingALineDropsItsTranslationAndDeletingTheVideoDropsAll() async throws {
        let (db, lines) = try await library(["La casa es grande", "Otra casa"])
        let service = TranslationService(database: db, translator: StubTranslator(), target: "en")
        _ = try await service.translate(lines)

        try await db.editSubtitle(id: lines[0].id!, text: "La casa es muy grande", profile: spanish)
        let left = try await db.translations(videoID: lines[0].videoId, target: "en")
        XCTAssertEqual(Array(left.keys), [lines[1].id!], "the edited line's translation was of the old text")

        _ = try await db.deleteVideoRows(id: lines[0].videoId)
        let count = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM translations") }
        XCTAssertEqual(count, 0, "they go with their video")
    }

    func testThePreferencesDefaultToOnRequestAndTheMacsLanguage() {
        let defaults = UserDefaults(suiteName: "tp-\(UUID().uuidString)")!
        let prefs = TranslationPreferences(defaults: defaults)
        XCTAssertEqual(prefs.display, .onRequest, "hidden until asked for")
        XCTAssertEqual(prefs.target, TranslationPreferences.systemLanguage)
        prefs.display = .always
        prefs.target = "fr"
        let again = TranslationPreferences(defaults: defaults)
        XCTAssertEqual([again.display, .always].count, 2)
        XCTAssertEqual(again.display, .always)
        XCTAssertEqual(again.target, "fr")
        prefs.display = .onRequest
        XCTAssertNil(defaults.string(forKey: TranslationPreferences.displayKey), "the default stores nothing")
    }

    func testAVideoIsNotTranslatedIntoItsOwnLanguage() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "tr-\(UUID().uuidString)")!
        let env = try LangEnvironment(root: dir, defaults: defaults)
        env.translation.target = "es"
        XCTAssertNil(env.translationService(for: spanish, translator: StubTranslator()), "a Spanish video on a Spanish setting")
        XCTAssertNotNil(env.translationService(for: JapaneseProfile(), translator: StubTranslator()))
        env.translation.target = "en"
        XCTAssertEqual(env.translationService(for: spanish, translator: StubTranslator())?.target, "en")
    }

    /// Needs the Spanish to English language data on this Mac, so it only runs where macOS has it.
    func testMacOSTranslatesARealLineWhenItsLanguageIsInstalled() async throws {
        let translator = AppleLineTranslator(source: "es", target: "en")
        let status = await translator.availability()
        try XCTSkipUnless(status == .ready, "Spanish to English isn't installed on this Mac (\(status))")
        let result = try await translator.translate(["Buenos días.", "♪", "Gracias."])
        XCTAssertEqual(result[0]?.lowercased().contains("morning"), true, "\(result)")
        XCTAssertNil(result[1], "a line with no words is left alone")
        XCTAssertEqual(result[2]?.lowercased().contains("thank"), true)
    }
}
