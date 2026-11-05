import XCTest
@testable import LangCore

final class ProfileNameTests: XCTestCase {
    func testNativeNameIsTheLanguageInItself() {
        let names = Dictionary(uniqueKeysWithValues: LanguageProfiles.all.map { ($0.code, $0.nativeName) })
        XCTAssertEqual(names["es"], "Español")
        XCTAssertEqual(names["fr"], "Français")
        XCTAssertEqual(names["de"], "Deutsch")
        XCTAssertEqual(names["ja"], "日本語")
    }

    func testEveryLanguageHasAFlagRegion() {
        for profile in LanguageProfiles.all { XCTAssertNotNil(profile.flagRegion, profile.code) }
    }
}
