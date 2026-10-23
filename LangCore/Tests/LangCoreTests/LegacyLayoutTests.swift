import XCTest
@testable import LangCore

/// The app was first called LangSRS; its data folder and database carried that name.
final class LegacyLayoutTests: XCTestCase {
    private func makeSupport() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testOldFolderAndDatabaseMoveToTheNewNames() throws {
        let support = try makeSupport()
        let old = support.appending(path: "LangSRS")
        try write("db", to: old.appending(path: "langsrs.sqlite"))
        try write("wal", to: old.appending(path: "langsrs.sqlite-wal"))
        try write("shm", to: old.appending(path: "langsrs.sqlite-shm"))
        try write("video", to: old.appending(path: "Library/abc/video.mov"))

        try LangEnvironment.migrateLegacyLayout(in: support)

        let new = support.appending(path: "Reprise")
        XCTAssertEqual(read(new.appending(path: "reprise.sqlite")), "db")
        XCTAssertEqual(read(new.appending(path: "reprise.sqlite-wal")), "wal")
        XCTAssertEqual(read(new.appending(path: "reprise.sqlite-shm")), "shm")
        XCTAssertEqual(read(new.appending(path: "Library/abc/video.mov")), "video", "everything else comes along")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertNil(read(new.appending(path: "langsrs.sqlite")))
    }

    func testNothingToDoWhenThereIsNoOldFolder() throws {
        let support = try makeSupport()
        try write("db", to: support.appending(path: "Reprise/reprise.sqlite"))
        try LangEnvironment.migrateLegacyLayout(in: support)
        XCTAssertEqual(read(support.appending(path: "Reprise/reprise.sqlite")), "db")
        try LangEnvironment.migrateLegacyLayout(in: try makeSupport())   // and nothing at all is fine
    }

    func testANewFolderThatAlreadyHoldsADatabaseIsNeverTouched() throws {
        let support = try makeSupport()
        try write("old data", to: support.appending(path: "LangSRS/langsrs.sqlite"))
        try write("new data", to: support.appending(path: "Reprise/reprise.sqlite"))

        try LangEnvironment.migrateLegacyLayout(in: support)

        XCTAssertEqual(read(support.appending(path: "Reprise/reprise.sqlite")), "new data")
        XCTAssertEqual(read(support.appending(path: "LangSRS/langsrs.sqlite")), "old data", "the old one stays where it was")
    }

    func testAnEmptyNewFolderIsSetAsideNotDeleted() throws {
        let support = try makeSupport()
        try write("old data", to: support.appending(path: "LangSRS/langsrs.sqlite"))
        try write("scratch", to: support.appending(path: "Reprise/Models/readme.txt"))   // no database in it

        try LangEnvironment.migrateLegacyLayout(in: support)

        XCTAssertEqual(read(support.appending(path: "Reprise/reprise.sqlite")), "old data")
        XCTAssertEqual(read(support.appending(path: "Reprise.before-migration/Models/readme.txt")), "scratch")
    }

    func testRunningItTwiceChangesNothingTheSecondTime() throws {
        let support = try makeSupport()
        try write("db", to: support.appending(path: "LangSRS/langsrs.sqlite"))
        try LangEnvironment.migrateLegacyLayout(in: support)
        try LangEnvironment.migrateLegacyLayout(in: support)
        XCTAssertEqual(read(support.appending(path: "Reprise/reprise.sqlite")), "db")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appending(path: "Reprise.before-migration").path))
    }
}
