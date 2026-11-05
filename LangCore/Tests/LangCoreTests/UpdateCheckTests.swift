import XCTest
@testable import LangCore

final class UpdateCheckTests: XCTestCase {
    private func json(_ version: String, _ url: String = "https://github.com/surreptus/kikimi/releases/latest") -> Data {
        Data(#"{"version": "\#(version)", "url": "\#(url)"}"#.utf8)
    }

    func testVersionsCompareNumberByNumberNotAsText() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.2")), try XCTUnwrap(AppVersion("0.14.0")), "14 is more than 9")
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.14")), try XCTUnwrap(AppVersion("0.14.1")), "a missing part is 0")
        XCTAssertEqual(try XCTUnwrap(AppVersion("1.0.0")), try XCTUnwrap(AppVersion("1.0")))
        XCTAssertEqual(try XCTUnwrap(AppVersion("0.15.0-beta")), try XCTUnwrap(AppVersion("0.15.0")), "a tag is ignored")
        XCTAssertNil(AppVersion("soon"))
        XCTAssertNil(AppVersion(""))
    }

    func testANewerVersionIsOfferedWithItsPage() {
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: json("0.15.0")),
                       .available(version: "0.15.0", page: URL(string: "https://github.com/surreptus/kikimi/releases/latest")!))
    }

    func testTheSameOrAnOlderVersionIsUpToDate() {
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: json("0.14.0")), .upToDate)
        XCTAssertEqual(UpdateCheck.outcome(current: "0.15.0", latest: json("0.14.0")), .upToDate, "a build ahead of the release")
    }

    func testAFileThatIsDamagedOrPointsElsewhereIsAFailureNotAnOffer() {
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: Data("not json".utf8)), .failed)
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: json("soon")), .failed)
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: json("0.15.0", "https://example.com/kikimi.zip")), .failed)
        XCTAssertEqual(UpdateCheck.outcome(current: "0.14.0", latest: json("0.15.0", "http://github.com/surreptus/kikimi")), .failed, "https only")
        XCTAssertEqual(UpdateCheck.outcome(current: "dev", latest: json("0.15.0")), .failed)
    }
}
