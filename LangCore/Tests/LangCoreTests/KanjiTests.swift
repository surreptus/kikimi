import GRDB
import XCTest
@testable import LangCore

final class KanjiTests: XCTestCase {
    private func makeStore() throws -> (KanjiStore, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "kanji-\(UUID().uuidString).sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE kanji (literal TEXT PRIMARY KEY, on_yomi TEXT NOT NULL, kun_yomi TEXT NOT NULL, meaning TEXT NOT NULL, jlpt INTEGER, grade INTEGER)")
            try db.execute(sql: "INSERT INTO kanji VALUES ('月', 'ゲツ、ガツ', 'つき', 'month; moon', 4, 1), ('食', 'ショク、ジキ', 'た.べる、く.う', 'eat; food', 3, 2)")
        }
        return (try KanjiStore(files: ["ja": url]), url)
    }

    func testListsEachKanjiOnceInWordOrderWithItsReadingsAndMeanings() async throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let found = try await store.kanji(in: "食べ月食", language: "ja")
        XCTAssertEqual(found.map(\.literal), ["食", "月"], "kana skipped, a repeated kanji listed once")
        XCTAssertEqual(found[1], KanjiInfo(literal: "月", onReadings: ["ゲツ", "ガツ"], kunReadings: ["つき"], meanings: ["month", "moon"], jlpt: 4, grade: 1))
        XCTAssertEqual(found[0].kunReadings, ["た.べる", "く.う"])
    }

    func testLevelsAreShownAsTodaysExamNamesThem() {
        func levels(_ jlpt: Int?) -> String? { KanjiInfo(literal: "x", onReadings: [], kunReadings: [], meanings: [], jlpt: jlpt).jlptLevels }
        XCTAssertEqual([4, 3, 2, 1].map(levels), ["N5", "N4", "N3–N2", "N1"])
        XCTAssertNil(levels(nil))
        XCTAssertNil(levels(7))
    }

    func testGradesBecomeSchoolYearsSecondaryOrNames() {
        func grade(_ grade: Int?) -> KanjiInfo.Grade? { KanjiInfo(literal: "x", onReadings: [], kunReadings: [], meanings: [], grade: grade).schoolGrade }
        XCTAssertEqual(grade(1), .year(1))
        XCTAssertEqual(grade(6), .year(6))
        XCTAssertEqual(grade(8), .secondary)
        XCTAssertEqual(grade(9), .names)
        XCTAssertEqual(grade(10), .names)
        XCTAssertNil(grade(nil))
        XCTAssertNil(grade(7))
    }

    /// A kanji file built before levels and grades were kept still opens.
    func testAnOlderKanjiFileHasNoLevels() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kanji-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try await queue.write { db in
            try db.execute(sql: "CREATE TABLE kanji (literal TEXT PRIMARY KEY, on_yomi TEXT NOT NULL, kun_yomi TEXT NOT NULL, meaning TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO kanji VALUES ('月', 'ゲツ、ガツ', 'つき', 'month; moon')")
        }
        let found = try await KanjiStore(files: ["ja": url]).kanji(in: "月", language: "ja")
        XCTAssertEqual(found.first?.meanings, ["month", "moon"])
        XCTAssertNil(found.first?.jlpt)
        XCTAssertNil(found.first?.grade)
    }

    func testNoKanjiDataForOtherLanguagesOrKanaOnlyWords() async throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let spanish = try await store.kanji(in: "月", language: "es")
        let kana = try await store.kanji(in: "たべる", language: "ja")
        let empty = try await store.kanji(in: "", language: "ja")
        XCTAssertEqual(spanish, [])
        XCTAssertEqual(kana, [])
        XCTAssertEqual(empty, [])
    }

    /// Only Japanese has a kanji file, and the one in the app has the common kanji.
    func testTheBundledFileCoversJapanese() async throws {
        XCTAssertEqual(LanguageProfiles.all.compactMap(\.kanjiResourceName), ["kanji-ja"])
        let store = try KanjiStore.bundled(for: LanguageProfiles.all)
        let found = try await store.kanji(in: "月", language: "ja")
        XCTAssertEqual(found.first?.onReadings, ["ゲツ", "ガツ"])
        XCTAssertEqual(found.first?.kunReadings, ["つき"])
        XCTAssertTrue(found.first?.meanings.contains("moon") == true)
    }
}
