import GRDB
import XCTest
@testable import LangCore

final class AppSupportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    /// One imported Spanish video with two lines, via the real save path.
    private func seededDatabase(dictionaries: DictionaryStore = .empty) async throws -> (LangDatabase, Video) {
        let db = try LangDatabase(dictionaries: dictionaries)
        let es = SpanishProfile()
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: "La casa es grande."),
            TranscriptSegment(start: 1, end: 2, text: "Corremos rápidamente a la casa."),
        ]
        let video = try await db.saveImport(
            video: Video(language: "es", title: "Clip", contentHash: "h", videoPath: "h/video.mov",
                         audioPath: "h/audio.m4a", duration: 2),
            subtitles: segments.map { (segment: $0, tokens: es.contentWords(in: $0.text)) })
        return (db, video)
    }

    private func wordID(_ db: LangDatabase, _ lemma: String) async throws -> Int64 {
        try await db.writer.read { try Word.filter(Column("lemma") == lemma).fetchOne($0)!.id! }
    }

    // MARK: Queries

    func testLibraryListsVideosWithSubtitleCounts() async throws {
        let (db, _) = try await seededDatabase()
        let items = try await db.libraryVideos(language: "es")
        XCTAssertEqual(items.map(\.subtitleCount), [2])
        let other = try await db.libraryVideos(language: "ja")
        XCTAssertTrue(other.isEmpty)
        let all = try await db.libraryVideos()
        XCTAssertEqual(all.count, 1)
    }

    func testWordsSortByFrequencyAndFilter() async throws {
        let (db, _) = try await seededDatabase()
        let rows = try await db.words(language: "es")
        XCTAssertEqual(rows.first?.word.lemma, "casa", "casa appears in both lines")
        XCTAssertEqual(rows.first?.occurrenceCount, 2)

        let search = try await db.words(language: "es", search: "COR")
        XCTAssertEqual(search.map(\.word.lemma), ["correr"])
        let none = try await db.words(language: "ja")
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchTreatsPercentAndUnderscoreLiterally() async throws {
        let (db, _) = try await seededDatabase()
        let percent = try await db.words(language: "es", search: "%")
        XCTAssertTrue(percent.isEmpty)
        let underscore = try await db.words(language: "es", search: "_")
        XCTAssertTrue(underscore.isEmpty)
    }

    func testStatusFilterAndToggles() async throws {
        let (db, _) = try await seededDatabase()
        let id = try await wordID(db, "casa")
        try await db.markKnown(wordID: id)
        var known = try await db.words(language: "es", status: .known)
        XCTAssertEqual(known.map(\.word.lemma), ["casa"])
        try await db.markNew(wordID: id)
        known = try await db.words(language: "es", status: .known)
        XCTAssertTrue(known.isEmpty)
        let reset = try await db.writer.read { try Word.fetchOne($0, key: id)! }
        XCTAssertEqual(reset.status, .new)
        XCTAssertNil(reset.stage)
    }

    func testExamplesComeFromYourVideos() async throws {
        let (db, _) = try await seededDatabase()
        let id = try await wordID(db, "casa")
        let lines = try await db.examples(wordID: id)
        XCTAssertEqual(lines.map(\.text), ["La casa es grande.", "Corremos rápidamente a la casa."])
        XCTAssertEqual(lines.first?.videoTitle, "Clip")
        XCTAssertEqual(lines.last?.startTime, 1)
    }

    // MARK: Review session

    func testReviewSessionFollowsWaniKaniRules() async throws {
        let (db, _) = try await seededDatabase()
        let a = try await wordID(db, "casa"), b = try await wordID(db, "grande")
        try await db.startLearning(wordID: a, now: now)
        try await db.startLearning(wordID: b, now: now)

        let session = try await ReviewSession(database: db, language: "es", now: now)
        let first = await session.remaining
        XCTAssertEqual(first, 2)

        // First card missed: drops/holds at stage 1 and comes back at the end.
        let card = try await session.currentCard()!
        try await session.answer(correct: false, now: now)
        let afterMiss = try await db.writer.read { try Word.fetchOne($0, key: card.id)! }
        XCTAssertEqual(afterMiss.stage, .apprentice1)

        // Second card correct: advances.
        let second = try await session.currentCard()!
        XCTAssertNotEqual(second.id, card.id)
        try await session.answer(correct: true, now: now)
        let advanced = try await db.writer.read { try Word.fetchOne($0, key: second.id)! }
        XCTAssertEqual(advanced.stage, .apprentice2)

        // The missed card returns; answering it right now does not advance it (stage changes once per session).
        let retry = try await session.currentCard()!
        XCTAssertEqual(retry.id, card.id)
        try await session.answer(correct: true, now: now)
        let unchanged = try await db.writer.read { try Word.fetchOne($0, key: card.id)! }
        XCTAssertEqual(unchanged.stage, .apprentice1)

        let done = try await session.currentCard()
        XCTAssertNil(done)
        let correctFirst = await session.correctFirstTry
        let total = await session.answered
        XCTAssertEqual(correctFirst, 1)
        XCTAssertEqual(total, 3)
    }

    func testReviewCardIncludesDictionaryEntryAndExample() async throws {
        let (db, _) = try await seededDatabase(
            dictionaries: TestDictionaries.store(["es": [("casa", nil, "1. (noun) house")]]))
        let id = try await wordID(db, "casa")
        try await db.startLearning(wordID: id, now: now)
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let card = try await session.currentCard()!
        XCTAssertEqual(card.entries.first?.gloss, "1. (noun) house")
        XCTAssertTrue(["La casa es grande.", "Corremos rápidamente a la casa."].contains(card.example?.text ?? ""),
                      "the card shows one of the word's example sentences")
    }

    func testEmptyQueue() async throws {
        let db = try LangDatabase()
        let session = try await ReviewSession(database: db, language: "es", now: now)
        let card = try await session.currentCard()
        XCTAssertNil(card)
    }

    // MARK: Models and acknowledgements

    /// Writes the files a usable model needs, optionally leaving some out.
    private func writeModel(at folder: URL, leaving out: Set<String> = []) throws {
        for file in ModelManager.requiredFiles where !out.contains(file) {
            let url = folder.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
    }

    func testModelManagerReportsOnlyCompleteInstalls() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "models/x/openai_whisper-tiny")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(["openai_whisper-tiny": "models/x/openai_whisper-tiny"]).write(to: dir.appending(path: "installed.json"))

        let manager = ModelManager(directory: dir)
        var installed = await manager.isInstalled("openai_whisper-tiny")
        XCTAssertFalse(installed, "index entry without model files is not an install")

        // The exact failure seen in the wild: the encoder folder exists but its weights never arrived.
        try writeModel(at: folder, leaving: ["AudioEncoder.mlmodelc/weights/weight.bin"])
        try FileManager.default.createDirectory(at: folder.appending(path: "AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        installed = await manager.isInstalled("openai_whisper-tiny")
        XCTAssertFalse(installed, "a missing weights file means the model can't load")

        try writeModel(at: folder)
        installed = await manager.isInstalled("openai_whisper-tiny")
        XCTAssertTrue(installed)
        let other = await manager.isInstalled("openai_whisper-medium")
        XCTAssertFalse(other)
    }

    func testDownloadRetriesAnIncompleteFetchThenSucceeds() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let calls = LockedBox(0)
        let manager = ModelManager(directory: dir) { [self] variant, base, _ in
            let folder = base.appending(path: "models/x/\(variant)")
            let attempt = calls.mutateReturning { $0 += 1; return $0 }
            // First attempt drops the encoder weights, as a dropped connection did.
            try writeModel(at: folder, leaving: attempt == 1 ? ["AudioEncoder.mlmodelc/weights/weight.bin"] : [])
            return folder
        }
        let folder = try await manager.download(variant: "openai_whisper-medium") { _ in }
        XCTAssertEqual(calls.value, 2)
        let installed = await manager.isInstalled("openai_whisper-medium")
        XCTAssertTrue(installed)
        XCTAssertTrue(folder.path.hasSuffix("openai_whisper-medium"))
    }

    func testDownloadGivesUpWithAClearErrorAndNoStaleEntry() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModelManager(directory: dir) { [self] variant, base, _ in
            let folder = base.appending(path: "models/x/\(variant)")
            try writeModel(at: folder, leaving: ["AudioEncoder.mlmodelc/weights/weight.bin"])
            return folder
        }
        do {
            try await manager.download(variant: "openai_whisper-medium", attempts: 2) { _ in }
            XCTFail("expected incomplete")
        } catch let ModelError.incomplete(model, missing) {
            XCTAssertEqual(model, "openai_whisper-medium")
            XCTAssertEqual(missing, ["AudioEncoder.mlmodelc/weights/weight.bin"])
        }
        let installed = await manager.isInstalled("openai_whisper-medium")
        XCTAssertFalse(installed)
        let message = ModelError.incomplete("m", missing: ["a"]).errorDescription ?? ""
        XCTAssertTrue(message.contains("download again"))
    }

    func testModelPreferencesOverrideAndReset() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let prefs = ModelPreferences(defaults: defaults)
        let ja = JapaneseProfile()
        XCTAssertEqual(prefs.model(for: ja), "openai_whisper-large-v3")
        prefs.setModel("openai_whisper-small", for: ja)
        XCTAssertEqual(prefs.model(for: ja), "openai_whisper-small")
        XCTAssertEqual(prefs.model(for: SpanishProfile()), "openai_whisper-medium", "other languages unaffected")
        prefs.setModel(nil, for: ja)
        XCTAssertEqual(prefs.model(for: ja), "openai_whisper-large-v3")
    }

    func testAcknowledgementsAreBundled() {
        let items = Acknowledgements.all()
        XCTAssertEqual(items.count, 7)
        XCTAssertTrue(items.contains { $0.title.contains("IPADIC") && $0.text.contains("Nara Institute") })
        XCTAssertTrue(items.contains { $0.title.contains("JMdict") && $0.text.contains("CC BY-SA") })
    }

    func testEnvironmentOpensTheBundledDictionariesInPlace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "env-\(UUID().uuidString)")!
        let env = try LangEnvironment(root: root, defaults: defaults)
        try await env.prepare()   // throws if a dictionary can't be opened or is empty
        XCTAssertEqual(env.database.dictionaries.languages, LanguageProfiles.all.map(\.code).sorted())
        for profile in LanguageProfiles.all {
            let count = try await env.database.dictionaries.entryCount(language: profile.code)
            XCTAssertGreaterThan(count, 1_000, profile.code)
        }
        try await env.prepare()   // a second launch has nothing to redo
        let size = try FileManager.default.attributesOfItem(atPath: root.appending(path: "langsrs.sqlite").path)[.size] as! Int
        XCTAssertLessThan(size, 2_000_000, "the dictionaries are not copied into the database")
    }
}


@MainActor
final class SentenceAudioTests: XCTestCase {
    private func line(_ id: Int64, media: String = "audio.m4a", start: Double = 0, end: Double = 1) throws -> ExampleLine {
        // ExampleLine is read from SQL; build one the same way.
        let queue = try DatabaseQueue()
        return try queue.read { db in
            try ExampleLine.fetchOne(db, sql: """
                SELECT ? AS subtitle_id, 'casa' AS surface, 'La casa' AS text, ? AS start_time, ? AS end_time,
                       1 AS video_id, 'Clip' AS video_title, ? AS media_path
                """, arguments: [id, start, end, media])!
        }
    }

    // MARK: Picker

    func testPickerChoosesRandomlyAmongAllExamples() throws {
        let examples = try (1...4).map { try line(Int64($0)) }
        var generator = SystemRandomNumberGenerator()
        var seen = Set<Int64>()
        for _ in 0..<200 { seen.insert(ExamplePicker.pick(from: examples, using: &generator)!.id) }
        XCTAssertEqual(seen, [1, 2, 3, 4], "every video's sentence is a candidate")
    }

    func testPickerAvoidsTheLastOneUnlessItIsTheOnlyChoice() throws {
        let examples = try (1...3).map { try line(Int64($0)) }
        for _ in 0..<100 { XCTAssertNotEqual(ExamplePicker.pick(from: examples, avoiding: 2)?.id, 2) }
        let only = try [line(7)]
        XCTAssertEqual(ExamplePicker.pick(from: only, avoiding: 7)?.id, 7)
        XCTAssertNil(ExamplePicker.pick(from: [], avoiding: nil))
    }

    // MARK: Cards

    func testCardKeepsItsSentenceAndVariesAcrossVisits() async throws {
        let db = try LangDatabase()
        let es = SpanishProfile()
        let lines = ["La casa es grande.", "Mi casa nueva.", "Vamos a la casa.", "Una casa antigua."]
        for (i, text) in lines.enumerated() {
            try await db.saveImport(
                video: Video(language: "es", title: "V\(i)", contentHash: "h\(i)", videoPath: "h\(i)/video.mov",
                             audioPath: "h\(i)/audio.m4a", duration: 5),
                subtitles: [(segment: TranscriptSegment(start: 0, end: 1, text: text), tokens: es.contentWords(in: text))])
        }
        let casa = try await db.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }

        var shown = Set<Int64>()
        for _ in 0..<30 {
            try await db.startLearning(wordID: casa, now: Date(timeIntervalSince1970: 0))
            let session = try await ReviewSession(database: db, language: "es", now: Date(timeIntervalSince1970: 1))
            let first = try await session.currentCard()!
            let again = try await session.currentCard()!
            XCTAssertEqual(first.example?.id, again.example?.id, "the sentence must not change under the user")
            XCTAssertTrue(first.example?.mediaPath.hasSuffix("audio.m4a") ?? false)
            shown.insert(first.example!.id)
        }
        XCTAssertGreaterThan(shown.count, 1, "different visits can show different videos' sentences")
    }

    func testMissedCardComesBackWithADifferentSentence() async throws {
        let db = try LangDatabase()
        let es = SpanishProfile()
        for (i, text) in ["La casa es grande.", "Mi casa nueva."].enumerated() {
            try await db.saveImport(
                video: Video(language: "es", title: "V\(i)", contentHash: "h\(i)", videoPath: "v", audioPath: "a", duration: 5),
                subtitles: [(segment: TranscriptSegment(start: 0, end: 1, text: text), tokens: es.contentWords(in: text))])
        }
        let casa = try await db.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        try await db.startLearning(wordID: casa, now: Date(timeIntervalSince1970: 0))
        let session = try await ReviewSession(database: db, language: "es", now: Date(timeIntervalSince1970: 1))
        let first = try await session.currentCard()!
        try await session.answer(correct: false)
        let second = try await session.currentCard()!
        XCTAssertNotEqual(first.example?.id, second.example?.id)
    }

    // MARK: Preferences

    func testModePreferencesDefaultToOnRevealAndAreRememberedPerLanguage() {
        let prefs = ReviewAudioPreferences(defaults: UserDefaults(suiteName: "sa-\(UUID().uuidString)")!)
        XCTAssertEqual(prefs.mode(for: SpanishProfile()), .onReveal)
        prefs.setMode(.onCardShown, for: SpanishProfile())
        XCTAssertEqual(prefs.mode(for: SpanishProfile()), .onCardShown)
        XCTAssertEqual(prefs.mode(for: JapaneseProfile()), .onReveal)
        prefs.setMode(.off, for: JapaneseProfile())
        XCTAssertEqual(prefs.mode(for: JapaneseProfile()), .off)
        XCTAssertEqual(SentenceAudioMode.allCases.count, 3)
    }

    // MARK: Player

    private func importedLibrary() async throws -> (LangEnvironment, ExampleLine) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "clip.mov")
        try await FixtureVideo.make(at: source, seconds: 6)
        let env = try LangEnvironment(
            root: dir.appending(path: "container"), defaults: UserDefaults(suiteName: "sa-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([
                TranscriptSegment(start: 1, end: 2, text: "La casa es grande."),
                TranscriptSegment(start: 3.5, end: 5, text: "Corremos a la casa."),
            ])))
        _ = try await env.pipeline.importVideo(from: source, profile: SpanishProfile())
        let casa = try await env.database.writer.read { try Word.filter(Column("lemma") == "casa").fetchOne($0)!.id! }
        let lines = try await env.database.examples(wordID: casa)
        return (env, lines.first { $0.text.hasPrefix("La casa") }!)
    }

    func testPlayerPlaysOnlyTheSentenceThenStops() async throws {
        let (env, line) = try await importedLibrary()
        let player = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        player.isMuted = true   // the fixture's audio is a tone
        let started = Date()
        let played = await player.play(line)
        XCTAssertTrue(played)
        XCTAssertTrue(player.isPlaying)

        var stopped = false
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            if !player.isPlaying { stopped = true; break }
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(stopped, "should stop on its own after the sentence")
        XCTAssertEqual(elapsed, 1.3, accuracy: 0.6, "1 s sentence + 0.3 s padding, not the whole 6 s file")
    }

    func testStopAndReplaceAndMissingFile() async throws {
        let (env, line) = try await importedLibrary()
        let player = SentenceAudioPlayer(libraryRoot: env.libraryURL)
        player.isMuted = true
        await player.play(line)
        player.stop()
        XCTAssertFalse(player.isPlaying)

        // A newer play() wins over one still seeking.
        async let first = player.play(line)
        async let second = player.play(line)
        _ = await (first, second)
        XCTAssertTrue(player.isPlaying)
        player.stop()

        var ghost = line
        ghost = try { let l = try ExampleLine(row: Row(["subtitle_id": 1, "surface": "x", "text": "t", "start_time": 0.0,
            "end_time": 1.0, "video_id": 1, "video_title": "v", "media_path": "nope/audio.m4a"])); return l }()
        let ok = await player.play(ghost)
        XCTAssertFalse(ok, "missing audio is reported, not a crash")
        XCTAssertFalse(player.isPlaying)
    }
}

final class BulkActionTests: XCTestCase {
    private func words(_ db: LangDatabase, count: Int) async throws -> [Int64] {
        try await db.writer.write { d in
            try (0..<count).map { i in
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun)
                try w.insert(d)
                return w.id!
            }
        }
    }

    private func fetch(_ db: LangDatabase, _ id: Int64) async throws -> Word {
        try await db.writer.read { try Word.fetchOne($0, key: id)! }
    }

    func testStartLearningManyLeavesProgressedWordsAlone() async throws {
        let db = try LangDatabase()
        let ids = try await words(db, count: 4)
        let now = Date(timeIntervalSince1970: 100)
        try await db.startLearning(wordID: ids[0], now: now)
        _ = try await db.recordReview(wordID: ids[0], correct: true, now: now)   // apprentice 2
        try await db.markKnown(wordID: ids[1])

        let changed = try await db.startLearning(wordIDs: ids, now: now)

        XCTAssertEqual(changed, 3, "the already-learning word is skipped")
        let progressed = try await fetch(db, ids[0])
        XCTAssertEqual(progressed.stage, .apprentice2, "an existing stage is never reset")
        let formerlyKnown = try await fetch(db, ids[1])
        XCTAssertEqual(formerlyKnown.status, .learning)
        XCTAssertEqual(formerlyKnown.stage, .apprentice1)
        XCTAssertEqual(formerlyKnown.nextReview, now)
        let due = try await db.dueWords(language: "es", now: now).count
        XCTAssertEqual(due, 3 + 0, "word 0 isn't due yet; the other three are")
    }

    func testMarkKnownAndResetMany() async throws {
        let db = try LangDatabase()
        let ids = try await words(db, count: 3)
        try await db.startLearning(wordIDs: ids)

        let known = try await db.markKnown(wordIDs: ids)
        XCTAssertEqual(known, 3)
        for id in ids {
            let w = try await fetch(db, id)
            XCTAssertEqual(w.status, .known)
            XCTAssertNil(w.stage)
            XCTAssertNil(w.nextReview)
        }
        let reset = try await db.markNew(wordIDs: [ids[0], ids[1]])
        XCTAssertEqual(reset, 2)
        let still = try await fetch(db, ids[2])
        XCTAssertEqual(still.status, .known)
        let fresh = try await fetch(db, ids[0])
        XCTAssertEqual(fresh.status, .new)
    }

    func testHandlesThousandsOfWordsAndEmptySelection() async throws {
        let db = try LangDatabase()
        let ids = try await words(db, count: 1_300)   // more than one internal batch
        let changed = try await db.markKnown(wordIDs: ids)
        XCTAssertEqual(changed, 1_300)
        let none = try await db.markKnown(wordIDs: [])
        XCTAssertEqual(none, 0)
        let all = try await db.words(language: "es", status: .known)
        XCTAssertEqual(all.count, 1_300, "the list isn't capped at 500")
    }
}
