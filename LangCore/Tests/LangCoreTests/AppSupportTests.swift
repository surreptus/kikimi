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

    func testOnlyWordsStillNewMayBeTaught() async throws {
        let (db, _) = try await seededDatabase()
        let casa = try await wordID(db, "casa"), grande = try await wordID(db, "grande"), correr = try await wordID(db, "correr")
        try await db.markKnown(wordID: casa)
        try await db.markIgnored(wordIDs: [grande])
        let before = try await db.stillNew([correr, casa, grande, 99_999])
        XCTAssertEqual(before, [correr], "known, ignored and missing words are left out")
        try await db.startLearning(wordID: correr, now: now)
        let after = try await db.stillNew([correr, casa, grande])
        XCTAssertEqual(after, [], "a word already in your reviews is not new")
        let order = try await db.stillNew([])
        XCTAssertEqual(order, [])
    }

    func testABulkActionCanBeUndoneExactly() async throws {
        let (db, _) = try await seededDatabase()
        let casa = try await wordID(db, "casa"), grande = try await wordID(db, "grande")
        let today = Date()
        try await db.startLearning(wordID: grande, now: today)   // already in your reviews before the action
        let before = try await db.snapshot(of: [casa, grande])

        try await db.startLearning(wordIDs: [casa, grande], now: today)   // only casa changes
        try await db.markKnown(wordIDs: [grande])
        let startedBefore = try await db.startedToday(language: "es", now: today)
        XCTAssertEqual(startedBefore, 2)

        let restored = try await db.restore(before, now: today)
        XCTAssertEqual(restored, 2)
        let words = try await db.writer.read { try Word.fetchAll($0, keys: [casa, grande]) }.sorted { $0.id! < $1.id! }
        let c = try XCTUnwrap(words.first { $0.id == casa }), g = try XCTUnwrap(words.first { $0.id == grande })
        XCTAssertEqual(c.status, .new)
        XCTAssertNil(c.stage)
        XCTAssertNil(c.nextReview)
        XCTAssertEqual(g.status, .learning, "back to learning, as it was")
        XCTAssertEqual(g.stage, .stage1)
        let startedAfter = try await db.startedToday(language: "es", now: today)
        XCTAssertEqual(startedAfter, 1, "casa's start is taken off today's tally; grande's earlier one stays")
    }

    func testAResetWordThatWasRemovedComesBack() async throws {
        let (db, _) = try await seededDatabase()
        let orphan = try await db.writer.write { db -> Int64 in
            var word = Word(language: "es", lemma: "zzz", pos: .noun, status: .learning, stage: .stage3, nextReview: Date())
            try word.insert(db)
            return word.id!
        }
        let before = try await db.snapshot(of: [orphan])
        try await db.markNew(wordIDs: [orphan])   // no line has it, so a reset removes it
        let gone = try await db.snapshot(of: [orphan])
        XCTAssertTrue(gone.isEmpty)
        try await db.restore(before)
        let back = try await db.snapshot(of: [orphan])
        XCTAssertEqual(back.first?.lemma, "zzz")
        XCTAssertEqual(back.first?.status, .learning)
        XCTAssertEqual(back.first?.stage, .stage3)
        XCTAssertEqual(back.first?.id, orphan)
    }

    func testOnlyNewWordsOfTheVideoAreOfferedForCalibration() async throws {
        let (db, _) = try await seededDatabase()
        let video = try await db.writer.read { try XCTUnwrap(try Video.fetchOne($0)).id! }
        let all = try await db.calibrationWords(videoID: video)
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.map(\.seen), all.map(\.seen).sorted(by: >), "most-seen first")
        let first = all[0].id, second = all[1].id
        try await db.markKnown(wordID: first)
        try await db.markIgnored(wordIDs: [second])
        let after = try await db.calibrationWords(videoID: video)
        XCTAssertFalse(after.contains { $0.id == first || $0.id == second }, "known and ignored words are not offered")
        XCTAssertEqual(after.count, all.count - 2)
    }

    func testANewVideoIsUnwatchedUntilItIsPlayedOrTheWindowPasses() async throws {
        let (db, video) = try await seededDatabase()
        let id = try XCTUnwrap(video.id)
        let waiting = try await db.unwatchedVideoIDs(language: "es")
        XCTAssertEqual(waiting, [id])
        let other = try await db.unwatchedVideoIDs(language: "ja")
        XCTAssertTrue(other.isEmpty, "only this language's videos")
        let later = Date().addingTimeInterval(LangDatabase.unwatchedWindow + 3600)
        let old = try await db.unwatchedVideoIDs(language: "es", now: later)
        XCTAssertTrue(old.isEmpty, "an old video is not pushed")
        try await db.record(.listen, subject: id, amount: 3)
        let played = try await db.unwatchedVideoIDs(language: "es")
        XCTAssertTrue(played.isEmpty, "playing it ends the offer")
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
        XCTAssertEqual(afterMiss.stage, .stage1)

        // Second card correct: advances.
        let second = try await session.currentCard()!
        XCTAssertNotEqual(second.id, card.id)
        try await session.answer(correct: true, now: now)
        let advanced = try await db.writer.read { try Word.fetchOne($0, key: second.id)! }
        XCTAssertEqual(advanced.stage, .stage2)

        // The missed card returns; answering it right now does not advance it (stage changes once per session).
        let retry = try await session.currentCard()!
        XCTAssertEqual(retry.id, card.id)
        try await session.answer(correct: true, now: now)
        let unchanged = try await db.writer.read { try Word.fetchOne($0, key: card.id)! }
        XCTAssertEqual(unchanged.stage, .stage1)

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
        let manager = ModelManager(directory: dir, manifest: .unchecked("openai_whisper-medium")) { [self] variant, base, _ in
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
        let manager = ModelManager(directory: dir, manifest: .unchecked("openai_whisper-medium")) { [self] variant, base, _ in
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
        XCTAssertEqual(prefs.model(for: ja), ja.defaultModel)
        prefs.setModel("openai_whisper-small", for: ja)
        XCTAssertEqual(prefs.model(for: ja), "openai_whisper-small")
        XCTAssertEqual(prefs.model(for: SpanishProfile()), "openai_whisper-medium", "other languages unaffected")
        prefs.setModel(nil, for: ja)
        XCTAssertEqual(prefs.model(for: ja), ja.defaultModel)
    }

    func testAcknowledgementsAreBundled() {
        let items = Acknowledgements.all()
        XCTAssertEqual(items.count, 10)
        XCTAssertTrue(items.contains { $0.title.contains("KANJIDIC2") && $0.text.contains("CC BY-SA 4.0") })
        XCTAssertTrue(items.contains { $0.title.contains("Kikimi") && $0.text.contains("MIT License") })
        // WhisperKit ships code from swift-transformers under the Apache licence, which has to travel with the app.
        XCTAssertTrue(items.contains { $0.title.contains("swift-transformers") && $0.text.contains("Apache License") && $0.text.contains("Hugging Face") })
        XCTAssertTrue(items.contains { $0.title.contains("IPADIC") && $0.text.contains("Nara Institute") })
        XCTAssertTrue(items.contains { $0.title.contains("JMdict") && $0.text.contains("CC BY-SA") })
    }

    /// A licence file added without a title would be bundled but never shown, so every file must be listed.
    func testEveryBundledLicenceFileIsListedInTheAcknowledgements() throws {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Licenses", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".txt") }
        XCTAssertEqual(Acknowledgements.all().count, files.count, "every file in Licenses/ has an entry")
    }

    /// The app shows its own licence from a copy in the bundle; it must be the repository's LICENSE.
    func testTheBundledCopyOfTheAppsLicenceIsTheRepositorysLicence() throws {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let license = try String(contentsOf: repoRoot.appending(path: "LICENSE"), encoding: .utf8)
        let bundled = try XCTUnwrap(Acknowledgements.all().first { $0.title.contains("Kikimi") })
        XCTAssertEqual(bundled.text, license)
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
        let size = try FileManager.default.attributesOfItem(atPath: root.appending(path: LangEnvironment.databaseName).path)[.size] as! Int
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
        XCTAssertEqual(player.playingLineID, line.id)

        var stopped = false
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            if !player.isPlaying { stopped = true; break }
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(stopped, "should stop on its own after the sentence")
        // The sentence plus padding is about 1.6 s of audio; the whole file from there would be about 5.3 s. The wall
        // clock also includes the audio pipeline starting, which varies by a second with the machine's state, so
        // the window is wide: it only has to tell "the sentence" from "the whole file".
        XCTAssertGreaterThan(elapsed, 1.0, "it should actually play")
        XCTAssertLessThan(elapsed, 3.5, "the sentence plus padding, not the whole 6 s file")
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
        XCTAssertNil(player.playingLineID, "starting another line replaces the one that was playing")
    }
}

final class BulkActionTests: XCTestCase {
    /// Words that appear in a line, as words found in a video do (a reset removes a word that is in no line).
    private func words(_ db: LangDatabase, count: Int) async throws -> [Int64] {
        try await db.writer.write { d in
            var video = Video(language: "es", title: "v", contentHash: "bulk", videoPath: "bulk/v", duration: 5)
            try video.insert(d)
            var line = Subtitle(videoId: video.id!, idx: 0, startTime: 0, endTime: 1, text: "w")
            try line.insert(d)
            return try (0..<count).map { i in
                var w = Word(language: "es", lemma: "w\(i)", pos: .noun)
                try w.insert(d)
                var occurrence = Occurrence(wordId: w.id!, subtitleId: line.id!, surface: "w\(i)")
                try occurrence.insert(d)
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
        XCTAssertEqual(progressed.stage, .stage2, "an existing stage is never reset")
        let formerlyKnown = try await fetch(db, ids[1])
        XCTAssertEqual(formerlyKnown.status, .learning)
        XCTAssertEqual(formerlyKnown.stage, .stage1)
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

final class VideoThumbnailTests: XCTestCase {
    func testAFrameComesBackAtMostTheRequestedSize() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "thumb-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url, seconds: 2, size: (640, 360))
        let image = await VideoThumbnail.image(for: url, duration: 2, maxSize: 200)
        XCTAssertNotNil(image)
        XCTAssertLessThanOrEqual(max(image?.width ?? 999, image?.height ?? 999), 200)
        let missing = await VideoThumbnail.image(for: url.appending(path: "nope"), duration: 2)
        XCTAssertNil(missing, "an unreadable file gives no thumbnail, not a crash")
    }
}

final class LibraryResetTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "reset-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "Library/h"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Models/m"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Staging"), withIntermediateDirectories: true)
        for name in ["kikimi.sqlite", "kikimi.sqlite-wal", "Library/h/video.mov", "Models/m/weights.bin"] {
            try Data(name.utf8).write(to: root.appending(path: name))
        }
        return root
    }

    func testTheLibraryIsMovedAsideAndNothingIsDeleted() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try XCTUnwrap(try LibraryReset.setAside(root: root, now: Date(timeIntervalSince1970: 0)))
        let fm = FileManager.default
        for gone in ["kikimi.sqlite", "kikimi.sqlite-wal", "Library", "Staging"] {
            XCTAssertFalse(fm.fileExists(atPath: root.appending(path: gone).path), "\(gone) is no longer in place")
        }
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "Library/h/video.mov"), encoding: .utf8), "Library/h/video.mov")
        XCTAssertTrue(fm.fileExists(atPath: folder.appending(path: "kikimi.sqlite").path), "the database is set aside, not deleted")
        XCTAssertTrue(fm.fileExists(atPath: root.appending(path: "Models/m/weights.bin").path), "speech models stay")
        XCTAssertEqual(folder.deletingLastPathComponent().lastPathComponent, "Set Aside")
    }

    func testTheSetAsideFolderIsOnlyReportedOnceSomethingIsInIt() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(LibraryReset.setAsideFolder(root: root), "nothing set aside yet, so there is nothing to show")
        let folder = try XCTUnwrap(try LibraryReset.setAside(root: root, now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(LibraryReset.setAsideFolder(root: root), folder.deletingLastPathComponent())
        // An empty folder (everything was moved back or deleted by hand) is not worth showing.
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(LibraryReset.setAsideFolder(root: root))
    }

    func testNothingToMoveIsNotAnError() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try LibraryReset.setAside(root: root))
    }
}

final class ProblemReportTests: XCTestCase {
    func testTheIssueIsPrefilledWithOnlyTheVersions() throws {
        let url = try XCTUnwrap(ProblemReport.url(app: "0.15.2 (12)", system: "macOS 27.2"))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/surreptus/kikimi/issues/new")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.map(\.name), ["body"], "only the body is filled in, not a title or labels")
        let body = try XCTUnwrap(items.first?.value)
        XCTAssertTrue(body.contains("Kikimi 0.15.2 (12) · macOS 27.2"))
        XCTAssertTrue(body.contains("What happened?"))
        XCTAssertTrue(body.contains("leave out personal details"))
    }
}

final class CalibrationTests: XCTestCase {
    private func word(_ id: Int64, seen: Int = 1) -> CalibrationWord { CalibrationWord(id: id, lemma: "w\(id)", seen: seen) }

    func testWordsAreShownInBatchesOfTwentyUpToSix() {
        let words = (1...200).map { word(Int64($0)) }
        let batches = Calibration.batches(of: words)
        XCTAssertEqual(batches.count, 6)
        XCTAssertEqual(batches.map(\.count), [20, 20, 20, 20, 20, 20], "120 words at most")
        XCTAssertEqual(batches[1].first?.id, 21)
        XCTAssertEqual(Calibration.batches(of: (1...25).map { word(Int64($0)) }).map(\.count), [20, 5])
        XCTAssertTrue(Calibration.batches(of: []).isEmpty)
    }

    func testThePassEndsWhenFewerThanHalfOfABatchIsKnown() {
        let batch = (1...20).map { word(Int64($0)) }
        XCTAssertTrue(Calibration.endsAfter(batch, known: Set(1...9)), "9 of 20 is less than half")
        XCTAssertFalse(Calibration.endsAfter(batch, known: Set(1...10)), "10 of 20 is half: go on")
        XCTAssertFalse(Calibration.endsAfter(batch, known: Set(1...20)), "all known: go on")
        XCTAssertTrue(Calibration.endsAfter(batch, known: []), "none known: that is enough")
        XCTAssertTrue(Calibration.endsAfter([], known: []), "nothing left to ask")
    }

    func testOnlyTheWordsYouTickedAreKnown() {
        let first = (1...3).map { word(Int64($0)) }, second = (4...6).map { word(Int64($0)) }
        XCTAssertEqual(Calibration.known(shown: [first, second], ticked: [2, 5]), [2, 5])
        XCTAssertEqual(Calibration.known(shown: [first], ticked: []), [])
        XCTAssertEqual(Calibration.known(shown: [first], ticked: [4]), [], "a word not shown is never marked")
        XCTAssertEqual(Calibration.known(shown: [], ticked: [1]), [])
    }
}

final class TextScaleTests: XCTestCase {
    func testTheUsualSizeChangesNothingAndEachStepIsLarger() {
        XCTAssertEqual(TextScale.standard.scaled(14), 14)
        let sizes = TextScale.allCases.map { $0.scaled(14) }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(sizes, [14, 16, 18, 21])
        XCTAssertGreaterThanOrEqual(TextScale.standard.scaled(12), 12, "the smallest text is never made smaller")
    }

    func testTheChoiceIsRememberedAndTheUsualSizeIsNoChoice() {
        let defaults = UserDefaults(suiteName: "ts-\(UUID().uuidString)")!
        XCTAssertEqual(TextScale.stored(in: defaults), .standard)
        TextScale.larger.store(in: defaults)
        XCTAssertEqual(TextScale.stored(in: defaults), .larger)
        TextScale.standard.store(in: defaults)
        XCTAssertNil(defaults.string(forKey: TextScale.key))
        defaults.set("huge", forKey: TextScale.key)
        XCTAssertEqual(TextScale.stored(in: defaults), .standard, "a size this version doesn't know is the usual one")
    }

    func testStepsStopAtTheEnds() {
        XCTAssertEqual(TextScale.standard.smaller, .standard)
        XCTAssertEqual(TextScale.standard.larger, .large)
        XCTAssertEqual(TextScale.largest.larger, .largest)
        XCTAssertEqual(TextScale.largest.smaller, .larger)
    }
}
