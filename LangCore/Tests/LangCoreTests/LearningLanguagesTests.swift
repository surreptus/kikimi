import XCTest
@testable import LangCore

final class LearningLanguagesTests: XCTestCase {
    private func make() -> LearningLanguages {
        LearningLanguages(defaults: UserDefaults(suiteName: "learning-\(UUID().uuidString)")!)
    }

    func testUnsetUntilChosen() {
        let learning = make()
        XCTAssertNil(learning.codes)
        XCTAssertEqual(learning.profiles.map(\.code), LanguageProfiles.all.map(\.code))
    }

    func testKeepsChoiceInRegistryOrder() {
        let learning = make()
        learning.codes = ["ja", "de"]
        XCTAssertEqual(learning.codes, ["de", "ja"])
        XCTAssertEqual(learning.profiles.map(\.code), ["de", "ja"])
    }

    func testIgnoresUnknownCodesAndEmptyChoices() {
        let learning = make()
        learning.codes = ["fr", "xx"]
        XCTAssertEqual(learning.codes, ["fr"])
        learning.codes = []
        XCTAssertNil(learning.codes)
        learning.codes = ["xx"]
        XCTAssertNil(learning.codes)
    }

    func testEnvironmentExposesIt() throws {
        let defaults = UserDefaults(suiteName: "learning-\(UUID().uuidString)")!
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let env = try LangEnvironment(root: root, defaults: defaults, dictionaries: .empty)
        env.learning.codes = ["es"]
        XCTAssertEqual(LearningLanguages(defaults: defaults).codes, ["es"])
    }
}
