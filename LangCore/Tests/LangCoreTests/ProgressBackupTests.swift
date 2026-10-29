import XCTest
import GRDB
@testable import LangCore

final class ProgressBackupTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    private func word(_ db: LangDatabase, _ lemma: String, _ pos: PartOfSpeech = .noun, language: String = "es",
                      status: WordStatus = .new, stage: SRSStage? = nil, due: Date? = nil) async throws {
        try await db.writer.write {
            var w = Word(language: language, lemma: lemma, pos: pos, status: status, stage: stage, nextReview: due)
            try w.insert($0)
        }
    }

    private func fetch(_ db: LangDatabase, _ lemma: String, language: String = "es") async throws -> Word? {
        try await db.writer.read {
            try Word.filter(Column("language") == language && Column("lemma") == lemma).fetchOne($0)
        }
    }

    private func sampleSource() async throws -> LangDatabase {
        let db = try LangDatabase()
        try await word(db, "casa", status: .learning, stage: .stage5, due: now.addingTimeInterval(7 * 86_400))
        try await word(db, "abrir", .verb, status: .known)
        try await word(db, "ventana", status: .finished, stage: .finished)
        try await word(db, "mesa")                                        // new: not exported
        try await word(db, "友達", language: "ja", status: .learning, stage: .stage2, due: now)
        return db
    }

    // MARK: Export

    func testExportHoldsOnlyWordsYouHaveWorkedOnInAStableOrder() async throws {
        let backup = try await sampleSource().exportProgress(now: now)
        XCTAssertEqual(backup.words.map(\.lemma), ["abrir", "casa", "ventana", "友達"], "language, then lemma; no new words")
        XCTAssertEqual(backup.words.first { $0.lemma == "casa" }?.stage, SRSStage.stage5.rawValue)
        XCTAssertNil(backup.words.first { $0.lemma == "abrir" }?.stage)
        XCTAssertEqual(backup.format, "aomame-progress")
        XCTAssertEqual(backup.version, 1)
    }

    func testTheFileIsReadablePlainJSON() async throws {
        let data = try await sampleSource().exportProgress(now: now).encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"format\" : \"aomame-progress\""))
        XCTAssertTrue(text.contains("\"lemma\" : \"casa\""))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data))
        XCTAssertEqual(ProgressBackup.fileExtension, "aomame")
    }

    // MARK: Round trip

    func testRestoringIntoAnEmptyLibraryKeepsEveryStatusStageAndDate() async throws {
        let data = try await sampleSource().exportProgress(now: now).encoded()
        let target = try LangDatabase()

        let report = try await target.importProgress(ProgressBackup.decode(data), now: now)

        XCTAssertEqual(report.added, 4)
        XCTAssertEqual(report.restored + report.kept + report.skipped, 0)
        let casa = try await fetch(target, "casa")
        XCTAssertEqual(casa?.status, .learning)
        XCTAssertEqual(casa?.stage, .stage5)
        XCTAssertEqual(casa?.nextReview, now.addingTimeInterval(7 * 86_400), "dates survive the file exactly")
        let known = try await fetch(target, "abrir")
        XCTAssertEqual(known?.status, .known)
        let burned = try await fetch(target, "ventana")
        XCTAssertEqual(burned?.stage, .finished)
        let ja = try await fetch(target, "友達", language: "ja")
        XCTAssertEqual(ja?.stage, .stage2)
        let mesa = try await fetch(target, "mesa")
        XCTAssertNil(mesa, "a word that was new isn't invented")
    }

    func testRestoredWordsAttachToTheirSentencesWhenTheVideoIsAddedLater() async throws {
        let data = try await sampleSource().exportProgress(now: now).encoded()
        let target = try LangDatabase()
        try await target.importProgress(ProgressBackup.decode(data), now: now)

        let video = Video(language: "es", title: "v", contentHash: "h", videoPath: "v", duration: 5)
        let tokens = [Token(surface: "casa", lemma: "casa", pos: .noun, reading: nil),
                      Token(surface: "mesa", lemma: "mesa", pos: .noun, reading: nil)]
        _ = try await target.saveImport(video: video, subtitles: [(TranscriptSegment(start: 0, end: 1, text: "la casa y la mesa"), tokens)])

        let casa = try await fetch(target, "casa")
        XCTAssertEqual(casa?.status, .learning, "the restored progress is still there")
        XCTAssertEqual(casa?.stage, .stage5)
        let occurrences = try await target.writer.read { try Occurrence.filter(Column("word_id") == casa!.id!).fetchCount($0) }
        XCTAssertEqual(occurrences, 1, "and the word now has its sentence")
        let count = try await target.writer.read { try Word.filter(Column("lemma") == "casa").fetchCount($0) }
        XCTAssertEqual(count, 1, "no duplicate word was made")
    }

    // MARK: Merging

    func testAWordYouAlreadyWorkedOnIsKeptAndANewOneTakesTheBackup() async throws {
        let backup = try await sampleSource().exportProgress(now: now)
        let target = try LangDatabase()
        try await word(target, "casa")                                              // new here: takes the backup
        try await word(target, "abrir", .verb, status: .learning, stage: .stage3, due: now) // different here: kept
        try await word(target, "ventana", status: .finished, stage: .finished)           // the same: unchanged

        let report = try await target.importProgress(backup, now: now)

        XCTAssertEqual(report.restored, 1)
        XCTAssertEqual(report.kept, 1)
        XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(report.added, 1, "the Japanese word wasn't here at all")
        let casa = try await fetch(target, "casa")
        XCTAssertEqual(casa?.stage, .stage5)
        let abrir = try await fetch(target, "abrir")
        XCTAssertEqual(abrir?.status, .learning, "your own progress wins")
        XCTAssertEqual(abrir?.stage, .stage3)
    }

    func testImportingTheSameFileTwiceChangesNothingTheSecondTime() async throws {
        let backup = try await sampleSource().exportProgress(now: now)
        let target = try LangDatabase()
        let first = try await target.importProgress(backup, now: now)
        let second = try await target.importProgress(backup, now: now)
        XCTAssertEqual(first.changes, 4)
        XCTAssertEqual(second.changes, 0)
        XCTAssertEqual(second.unchanged, 4)
    }

    func testThePreviewMatchesWhatImportingDoesAndWritesNothing() async throws {
        let backup = try await sampleSource().exportProgress(now: now)
        let target = try LangDatabase()
        try await word(target, "casa")

        let preview = try await target.previewProgressImport(backup, now: now)
        let wordsAfterPreview = try await target.writer.read { try Word.fetchCount($0) }
        XCTAssertEqual(wordsAfterPreview, 1, "a preview changes nothing")
        let casaAfterPreview = try await fetch(target, "casa")
        XCTAssertEqual(casaAfterPreview?.status, .new)

        let real = try await target.importProgress(backup, now: now)
        XCTAssertEqual(preview, real)
    }

    // MARK: Bad files and bad entries

    func testFilesThatAreNotBackupsOrAreDamagedOrTooNewAreRefusedClearly() throws {
        XCTAssertThrowsError(try ProgressBackup.decode(Data("hello".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try ProgressBackup.decode(Data("{\"format\":\"something-else\",\"version\":1}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try ProgressBackup.decode(Data("{\"format\":\"aomame-progress\",\"version\":99}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(99))
        }
        XCTAssertThrowsError(try ProgressBackup.decode(Data("{\"format\":\"aomame-progress\",\"version\":1,\"words\":5}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .damaged)
        }
        for error in [BackupError.notABackup, .newerVersion(2), .damaged] { XCTAssertNotNil(error.errorDescription) }
    }

    func testEntriesThatCantBeTrustedAreSkippedAndTheRestStillRestore() async throws {
        let bad: [ProgressBackup.Entry] = [
            .init(language: "xx", lemma: "casa", pos: "noun", status: "known"),                       // unknown language
            .init(language: "es", lemma: "casa", pos: "planet", status: "known"),                     // unknown part of speech
            .init(language: "es", lemma: "casa", pos: "noun", status: "wrong"),                       // unknown status
            .init(language: "es", lemma: "casa", pos: "noun", status: "new"),                         // nothing to restore
            .init(language: "es", lemma: "casa", pos: "noun", status: "learning", stage: 0),          // stage out of range
            .init(language: "es", lemma: "casa", pos: "noun", status: "learning", stage: 9),          // 9 is burned, not learning
            .init(language: "es", lemma: "casa", pos: "noun", status: "learning"),                    // no stage
            .init(language: "es", lemma: "", pos: "noun", status: "known"),                           // no word
            .init(language: "es", lemma: "bueno", pos: "adjective", status: "known"),                 // fine
        ]
        let target = try LangDatabase()
        let report = try await target.importProgress(ProgressBackup(words: bad), now: now)
        XCTAssertEqual(report.skipped, 8)
        XCTAssertEqual(report.added, 1)
        let bueno = try await fetch(target, "bueno")
        XCTAssertEqual(bueno?.status, .known)
        let casa = try await fetch(target, "casa")
        XCTAssertNil(casa, "nothing half-valid was kept")
    }

    func testALearningWordWithoutADateIsDueNow() async throws {
        let backup = ProgressBackup(words: [.init(language: "es", lemma: "casa", pos: "noun", status: "learning", stage: 3)])
        let target = try LangDatabase()
        try await target.importProgress(backup, now: now)
        let due = try await target.dueWords(language: "es", now: now)
        XCTAssertEqual(due.map(\.lemma), ["casa"], "otherwise it would never come up for review")
    }

    // MARK: Settings

    func testSettingsRoundTripAndAFileCannotSetAnythingElse() async throws {
        let suite = "backup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "bk-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let env = try LangEnvironment(
            root: dir, defaults: defaults, transcriber: StubTranscriber(result: .success([])),
            dictionaries: TestDictionaries.store(["es": [("casa", nil, "house")], "ja": [("家", "いえ", "house")]]))

        let es = LanguageProfiles.profile(for: "es")!
        env.preferences.setModel("openai_whisper-small", for: es)
        env.reviewAudio.setMode(.onCardShown, for: es)
        let data = try await env.makeBackup(extraSettings: ["appearance": "dark"])

        // A different library with different settings, plus a hostile file that tries to set other things.
        env.preferences.setModel(nil, for: es)
        env.reviewAudio.setMode(.onReveal, for: es)
        let restored = try await env.restoreBackup(data, includingSettings: true, appSettingKeys: ["appearance"])
        XCTAssertEqual(env.preferences.model(for: es), "openai_whisper-small")
        XCTAssertEqual(env.reviewAudio.mode(for: es), .onCardShown)
        XCTAssertEqual(restored.appSettings, ["appearance": "dark"], "the app is handed only the keys it asked for")

        var hostile = try ProgressBackup.decode(data)
        hostile.settings = ["whisperModel.es": "not-a-model", "whisperModel.xx": "openai_whisper-tiny",
                            "sentenceAudio.es": "nonsense", "NSUserDefaultsSecret": "x", "appearance": "dark"]
        let hostileData = try hostile.encoded()
        env.preferences.setModel(nil, for: es)
        let result = try await env.restoreBackup(hostileData, includingSettings: true, appSettingKeys: ["appearance"])
        XCTAssertEqual(env.preferences.model(for: es), es.defaultModel, "an unknown model isn't accepted")
        XCTAssertEqual(result.appSettings, ["appearance": "dark"], "unknown keys are dropped")

        let off = try await env.restoreBackup(data, includingSettings: false, appSettingKeys: ["appearance"])
        XCTAssertTrue(off.appSettings.isEmpty)
        let preview = try await env.previewBackup(data, appSettingKeys: ["appearance"])
        XCTAssertGreaterThan(preview.settingsCount, 0)
    }

    func testThePreviewCountsWordsByStatusAndLanguage() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bk2-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let env = try LangEnvironment(
            root: dir, defaults: UserDefaults(suiteName: "bk2-\(UUID().uuidString)")!,
            transcriber: StubTranscriber(result: .success([])),
            dictionaries: TestDictionaries.store(["es": [("casa", nil, "house")], "ja": [("家", "いえ", "house")]]))
        let data = try await sampleSource().exportProgress(now: now).encoded()
        let preview = try await env.previewBackup(data)
        XCTAssertEqual(preview.learning, 2)
        XCTAssertEqual(preview.known, 1)
        XCTAssertEqual(preview.finished, 1)
        XCTAssertEqual(preview.languages, ["es", "ja"])
        XCTAssertEqual(preview.report.added, 4)
    }
}
