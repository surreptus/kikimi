import XCTest
import GRDB
@testable import LangCore

final class CoverageTests: XCTestCase {
    private struct Fixture {
        let db: LangDatabase
        let video: Int64
        let other: Int64
    }

    /// Video 1 has 10 content-word occurrences: casa x4 (known), mesa x2 (learning stage 5), perro x2 (learning stage 2),
    /// gato x1 (new), libro x1 (burned). Video 2 is Japanese with one known word.
    private func fixture() async throws -> Fixture {
        let db = try LangDatabase()
        return try await db.writer.write { d in
            var v = Video(language: "es", title: "uno", contentHash: "1", videoPath: "a", duration: 60); try v.insert(d)
            var j = Video(language: "ja", title: "dos", contentHash: "2", videoPath: "b", duration: 60); try j.insert(d)
            func word(_ lemma: String, _ status: WordStatus, _ stage: SRSStage?, language: String = "es") throws -> Int64 {
                var w = Word(language: language, lemma: lemma, pos: .noun, status: status, stage: stage); try w.insert(d); return w.id!
            }
            let casa = try word("casa", .known, nil), mesa = try word("mesa", .learning, .stage5)
            let perro = try word("perro", .learning, .stage2), gato = try word("gato", .new, nil)
            let libro = try word("libro", .finished, .finished), tomo = try word("友達", .known, nil, language: "ja")
            var line = 0
            func occur(_ wordID: Int64, times: Int, video: Int64) throws {
                for _ in 0..<times {
                    var s = Subtitle(videoId: video, idx: line, startTime: Double(line), endTime: Double(line) + 1, text: "x"); try s.insert(d)
                    var o = Occurrence(wordId: wordID, subtitleId: s.id!, surface: "x"); try o.insert(d)
                    line += 1
                }
            }
            try occur(casa, times: 4, video: v.id!); try occur(mesa, times: 2, video: v.id!)
            try occur(perro, times: 2, video: v.id!); try occur(gato, times: 1, video: v.id!)
            try occur(libro, times: 1, video: v.id!); try occur(tomo, times: 1, video: j.id!)
            return Fixture(db: db, video: v.id!, other: j.id!)
        }
    }

    func testCoverageCountsKnownBurnedAndEstablishedLearningWords() async throws {
        let f = try await fixture()
        let c = try await f.db.coverage(forVideo: f.video)
        XCTAssertEqual(c?.totalWords, 10)
        XCTAssertEqual(c?.knownWords, 7, "casa 4 + mesa 2 (stage 5 counts) + libro 1; perro (stage 2) and gato don't")
        XCTAssertEqual(c?.fraction ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(c?.unknownWords, 3)
    }

    func testTheStageWhereALearningWordCountsAsKnown() {
        XCTAssertFalse(SRSStage.stage4.isEstablished)
        XCTAssertTrue(SRSStage.stage5.isEstablished)
        XCTAssertTrue(SRSStage.stage8.isEstablished)
    }

    func testEachVideoGetsItsOwnCoverageAndLanguagesCanBeSeparated() async throws {
        let f = try await fixture()
        let all = try await f.db.videoCoverage()
        XCTAssertEqual(all[f.video]?.totalWords, 10)
        XCTAssertEqual(all[f.other]?.fraction, 1)
        let spanish = try await f.db.videoCoverage(language: "es")
        XCTAssertEqual(Set(spanish.keys), [f.video])
    }

    func testAVideoWithNoWordsHasNoFit() async throws {
        let db = try LangDatabase()
        let id = try await db.writer.write { d -> Int64 in
            var v = Video(language: "es", title: "silent", contentHash: "s", videoPath: "a", duration: 5); try v.insert(d); return v.id!
        }
        let c = try await db.coverage(forVideo: id)
        XCTAssertEqual(c?.totalWords, 0)
        XCTAssertEqual(c?.fraction, 0)
        XCTAssertNil(c?.fit)
    }

    // MARK: Fit bands and ordering

    func testFitBands() {
        XCTAssertEqual(LevelFit(fraction: 0.50), .hard)
        XCTAssertEqual(LevelFit(fraction: 0.799), .hard)
        XCTAssertEqual(LevelFit(fraction: 0.80), .stretch)
        XCTAssertEqual(LevelFit(fraction: 0.879), .stretch)
        XCTAssertEqual(LevelFit(fraction: 0.88), .comfortable)
        XCTAssertEqual(LevelFit(fraction: 0.979), .comfortable)
        XCTAssertEqual(LevelFit(fraction: 0.98), .easy)
        XCTAssertEqual(LevelFit(fraction: 1.0), .easy)
        for fit in LevelFit.allCases { XCTAssertFalse(fit.title.isEmpty) }
    }

    func testBestFirstPutsComfortableThenStretchThenEasyThenHard() {
        func cov(_ id: Int64, _ known: Int) -> VideoCoverage { VideoCoverage(videoID: id, totalWords: 100, knownWords: known) }
        let ordered = [cov(1, 60), cov(2, 100), cov(3, 84), cov(4, 93), cov(5, 90), cov(6, 0)]
            .sorted(by: VideoCoverage.bestFirst).map(\.videoID)
        // 93% is the ideal, then 90%; 84% is a stretch; 100% is easy; 60% is hard. A video with 0 known is hard too.
        XCTAssertEqual(ordered, [4, 5, 3, 2, 1, 6])
        let empty = VideoCoverage(videoID: 9, totalWords: 0, knownWords: 0)
        XCTAssertEqual(([empty, cov(1, 95)]).sorted(by: VideoCoverage.bestFirst).map(\.videoID), [1, 9], "nothing to judge goes last")
    }

    // MARK: Words to reach a target

    func testTheShortestListThatReachesTheTarget() async throws {
        let f = try await fixture()
        // 7 of 10 known. Unknown: perro x2, gato x1. To reach 90% (9 of 10) needs perro (2) -> 9/10.
        let goal = try await f.db.wordsToReach(target: 0.9, inVideo: f.video)
        XCTAssertEqual(goal?.words.map(\.lemma), ["perro"], "the commonest unknown word first, and stopping once reached")
        XCTAssertEqual(goal?.reachedFraction ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertEqual(goal?.isReached, false)
        // Reaching 100% needs both.
        let all = try await f.db.wordsToReach(target: 1.0, inVideo: f.video)
        XCTAssertEqual(all?.words.map(\.lemma), ["perro", "gato"])
        XCTAssertEqual(all?.reachedFraction ?? 0, 1, accuracy: 0.0001)
    }

    func testWordsAlreadyBeingLearnedStayOnTheListButOnlyNewOnesAreSuggestedForStarting() async throws {
        let f = try await fixture()
        let goal = try await f.db.wordsToReach(target: 1.0, inVideo: f.video)
        XCTAssertEqual(goal?.words.first { $0.lemma == "perro" }?.status, .learning)
        XCTAssertEqual(goal?.notStarted.map(\.lemma), ["gato"], "perro is already in your reviews")
    }

    func testAlreadyAtTheTargetNeedsNoWords() async throws {
        let f = try await fixture()
        let goal = try await f.db.wordsToReach(target: 0.5, inVideo: f.video)
        XCTAssertEqual(goal?.words, [])
        XCTAssertEqual(goal?.isReached, true)
        let none = try await f.db.wordsToReach(target: 0.9, inVideo: 9999)
        XCTAssertNil(none, "a video that doesn't exist")
    }

    func testRealisticSizeIsFast() async throws {
        let db = try LangDatabase()
        let video = try await db.writer.write { d -> Int64 in
            var v = Video(language: "es", title: "big", contentHash: "b", videoPath: "a", duration: 3600); try v.insert(d)
            var words: [Int64] = []
            for i in 0..<1500 { var w = Word(language: "es", lemma: "w\(i)", pos: .noun, status: i % 3 == 0 ? .known : .new); try w.insert(d); words.append(w.id!) }
            for i in 0..<12_000 {
                var s = Subtitle(videoId: v.id!, idx: i, startTime: Double(i), endTime: Double(i) + 1, text: "x"); try s.insert(d)
                var o = Occurrence(wordId: words[(i * 7) % words.count], subtitleId: s.id!, surface: "x"); try o.insert(d)
            }
            return v.id!
        }
        let started = Date()
        _ = try await db.videoCoverage()
        _ = try await db.wordsToReach(target: 0.9, inVideo: video)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0, "an hour of video: coverage and the word list")
    }
}
