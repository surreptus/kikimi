import GRDB
import XCTest
@testable import LangCore

final class ReanalysisTests: XCTestCase {
    /// A tokenizer that reads each space-separated word as a noun and maps its spelling to a lemma, so a test can
    /// stand for an old tokenizer (`[:]`) or a fixed one (a map with a correction).
    private struct StubTokenizer: WordTokenizer {
        var lemmas: [String: String] = [:]
        var drop: Set<String> = []
        func tokens(in text: String) -> [Token] {
            text.split(separator: " ").map { String($0) }.filter { !drop.contains($0) }
                .map { Token(surface: $0, lemma: lemmas[$0] ?? $0, pos: .noun) }
        }
    }

    private struct StubProfile: LanguageProfile {
        var code = "es"
        var displayName = "Stub"
        var whisperCode = "es"
        var defaultModel = "none"
        var tokenizer: any WordTokenizer
        var dictionarySource = DictionarySource(resourceName: "none", attribution: "")
        func dictationUnits(in text: String) -> [String] { text.split(separator: " ").map(String.init) }
        var dictationLimit: Int { 10 }
        var dictationSeparator: String { " " }
        init(_ tokenizer: StubTokenizer) { self.tokenizer = tokenizer }
    }

    private let lines = ["unas casas", "cargo la casa", "casas y casas"]
    private let old = StubProfile(StubTokenizer())
    private let fixed = StubProfile(StubTokenizer(lemmas: ["unas": "unir", "cargo": "cargar"], drop: ["y"]))

    /// Imports `lines` as one video, the way a pipeline import would, with the profile as it was then.
    private func library(_ texts: [String]? = nil, profile: StubProfile? = nil, language: String = "es") async throws -> LangDatabase {
        let db = try LangDatabase()
        try await addVideo(db, texts ?? lines, profile: profile ?? old, language: language, hash: "h")
        return db
    }

    @discardableResult
    private func addVideo(_ db: LangDatabase, _ texts: [String], profile: StubProfile, language: String = "es", hash: String) async throws -> Video {
        try await db.saveImport(
            video: Video(language: language, title: hash, contentHash: hash, videoPath: "\(hash)/video.mov", duration: 100),
            subtitles: texts.enumerated().map {
                (TranscriptSegment(start: Double($0.offset), end: Double($0.offset) + 0.9, text: $0.element), profile.contentWords(in: $0.element))
            })
    }

    private func run(_ db: LangDatabase, _ profile: StubProfile) async throws -> ReanalysisReport {
        try await db.reanalyseWords(profileFor: { _ in profile })
    }

    private func occurrences(_ db: LangDatabase) async throws -> [String] {
        try await db.writer.read {
            try String.fetchAll($0, sql: """
                SELECT subtitles.text || '|' || words.lemma || '|' || occurrences.surface FROM occurrences
                JOIN words ON words.id = occurrences.word_id JOIN subtitles ON subtitles.id = occurrences.subtitle_id
                ORDER BY 1
                """)
        }
    }

    private static func progress(_ w: Word) -> String { "\(w.id!) \(w.status) \(String(describing: w.stage)) \(String(describing: w.nextReview))" }

    private func word(_ db: LangDatabase, _ lemma: String) async throws -> Word? {
        try await db.writer.read { try Word.filter(Column("lemma") == lemma).fetchOne($0) }
    }

    private func dump(_ db: LangDatabase) async throws -> [String] {
        try await db.writer.read {
            try Row.fetchAll($0, sql: "SELECT 'o' || id || ':' || word_id || ':' || subtitle_id || ':' || surface AS s FROM occurrences UNION ALL SELECT 'w' || id || ':' || lemma || ':' || status AS s FROM words ORDER BY s")
                .map { $0["s"] as String }
        }
    }

    func testAFixedTokenizerAddsItsWords() async throws {
        let db = try await library()
        let report = try await run(db, fixed)
        let unir = try await word(db, "unir"), cargar = try await word(db, "cargar")
        XCTAssertEqual(unir?.status, .new)
        XCTAssertEqual(cargar?.status, .new)
        XCTAssertEqual(report.videosLooked, 1)
        XCTAssertEqual(report.wordsAdded, 2)
    }

    func testOccurrencesMatchAFreshImportOfTheSameLines() async throws {
        let db = try await library()
        _ = try await run(db, fixed)
        let fresh = try await library(profile: fixed)
        let a = try await occurrences(db), b = try await occurrences(fresh)
        XCTAssertEqual(a, b)
        // Example sentences are read from occurrences, so they match too.
        let id = try await word(db, "casa")!.id!, freshID = try await word(fresh, "casa")!.id!
        let seen = try await db.seen(wordID: id), freshSeen = try await fresh.seen(wordID: freshID)
        XCTAssertEqual(seen, freshSeen)
    }

    func testASecondRunChangesNothing() async throws {
        let db = try await library()
        _ = try await run(db, fixed)
        let before = try await dump(db)
        let report = try await run(db, fixed)
        let after = try await dump(db)
        XCTAssertEqual(before, after)
        XCTAssertEqual(report.wordsAdded, 0)
        XCTAssertEqual(report.wordsInNoVideo, 0)
    }

    func testProgressAndActivitySurviveAWordTheTokenizerNoLongerFinds() async throws {
        let db = try await library()
        let due = Date(timeIntervalSince1970: 5_000)
        let ids = try await db.writer.read { d in
            try ["unas", "cargo", "y", "casas"].map { lemma in try Word.filter(Column("lemma") == lemma).fetchOne(d)!.id! }
        }
        try await db.writer.write { d in
            try d.execute(sql: "UPDATE words SET status = 'learning', stage = 2, next_review = ? WHERE id = ?", arguments: [due, ids[0]])
            try d.execute(sql: "UPDATE words SET status = 'known' WHERE id = ?", arguments: [ids[1]])
            try d.execute(sql: "UPDATE words SET status = 'ignored' WHERE id = ?", arguments: [ids[2]])
            try d.execute(sql: "UPDATE words SET status = 'burned' WHERE id = ?", arguments: [ids[3]])
        }
        try await db.record(.learn, subject: ids[0])
        let before = try await db.snapshot(of: ids)
        let activityBefore = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM activity")! }

        // `fixed` reads "unas" as "unir", "cargo" as "cargar", and drops "y".
        let report = try await run(db, fixed)

        let after = try await db.snapshot(of: ids)
        XCTAssertEqual(before.map(Self.progress), after.map(Self.progress))
        let activityAfter = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM activity")! }
        XCTAssertEqual(activityBefore, activityAfter)
        // "unas", "cargo" and "y" are now in no video; "casas" still is.
        XCTAssertEqual(report.wordsInNoVideo, 3)
        for id in ids.prefix(3) {
            let n = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM occurrences WHERE word_id = ?", arguments: [id])! }
            XCTAssertEqual(n, 0)
        }
    }

    func testAChangedLemmaLeavesBothWordsWhenTheOldOneHasProgress() async throws {
        let db = try await library()
        try await db.writer.write { try $0.execute(sql: "UPDATE words SET status = 'known' WHERE lemma = 'cargo'") }
        _ = try await run(db, fixed)
        let oldWord = try await word(db, "cargo"), newWord = try await word(db, "cargar")
        XCTAssertNotNil(oldWord)
        XCTAssertNotNil(newWord)
        XCTAssertNotEqual(oldWord?.id, newWord?.id)
    }

    func testAnUntouchedWordThatNoVideoHasAnymoreIsRemovedAndOneWithAHistoryIsKept() async throws {
        let db = try await library()
        let looked = try await word(db, "cargo")   // looked up once, still `new`
        try await db.record(.lookup, subject: looked!.id!)
        let report = try await run(db, fixed)
        // "unas" (new, no activity) and "y" are gone; "cargo" (new, but looked up) stays.
        let unas = try await word(db, "unas"), y = try await word(db, "y"), cargo = try await word(db, "cargo")
        XCTAssertNil(unas)
        XCTAssertNil(y)
        XCTAssertNotNil(cargo)
        XCTAssertEqual(report.wordsRemoved, 2)
        XCTAssertEqual(report.wordsInNoVideo, 1)
        let second = try await run(db, fixed)
        XCTAssertEqual(second.wordsRemoved, 0, "a second run removes nothing more")
    }

    func testEditedLinesAreUsed() async throws {
        let db = try await library(["una casa"])
        let line = try await db.subtitles(videoID: 1).first!.id!
        try await db.editSubtitle(id: line, text: "cargo perro", profile: old)
        _ = try await run(db, fixed)
        let found = try await occurrences(db)
        XCTAssertEqual(found, ["cargo perro|cargar|cargo", "cargo perro|perro|perro"])
    }

    func testAFailureLeavesThatVideoAsItWasAndARunAfterwardFinishes() async throws {
        let db = try await library(["unas casas"])
        try await addVideo(db, ["cargo otra"], profile: old, hash: "second")
        // The second video cannot get a "cargar" word.
        try await db.writer.write { d in
            try d.execute(sql: """
                CREATE TRIGGER no_cargar BEFORE INSERT ON words WHEN NEW.lemma = 'cargar'
                BEGIN SELECT RAISE(ABORT, 'no'); END
                """)
        }
        let secondBefore = try await occurrences(db).filter { $0.hasPrefix("cargo otra") }
        do { _ = try await run(db, fixed); XCTFail("should fail") } catch {}
        // The first video is whole: its fixed word is there. The second is as it was.
        let unir = try await word(db, "unir")
        XCTAssertNotNil(unir)
        let cargar = try await word(db, "cargar")
        XCTAssertNil(cargar)
        let secondAfter = try await occurrences(db).filter { $0.hasPrefix("cargo otra") }
        XCTAssertEqual(secondBefore, secondAfter)
        try await db.writer.write { try $0.execute(sql: "DROP TRIGGER no_cargar") }
        let report = try await run(db, fixed)
        XCTAssertEqual(report.videosLooked, 2)
        let done = try await word(db, "cargar")
        XCTAssertNotNil(done)
    }

    func testAVideoWithNoProfileIsSkippedAndCounted() async throws {
        let db = try await library()
        try await addVideo(db, ["hello world"], profile: StubProfile(StubTokenizer()), language: "xx", hash: "other")
        let before = try await dump(db)
        let report = try await db.reanalyseWords(profileFor: { $0 == "es" ? self.old : nil })
        XCTAssertEqual(report.videosSkipped, 1)
        XCTAssertEqual(report.videosLooked, 1)
        let after = try await dump(db)
        XCTAssertEqual(before, after)
    }

    func testProgressIsReportedForEachVideo() async throws {
        let db = try await library()
        try await addVideo(db, ["otra"], profile: old, hash: "second")
        let steps = Locked<[Int]>([])
        _ = try await db.reanalyseWords(profileFor: { _ in self.old }, progress: { done, total in
            XCTAssertEqual(total, 2)
            steps.mutate { $0.append(done) }
        })
        XCTAssertEqual(steps.value, [0, 1, 2])
    }
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
