import XCTest
@testable import LangCore

final class VideoQualityTests: XCTestCase {
    let spanish = SpanishProfile()

    func testKeepingTheOriginalStoresTheFileUntouchedWithoutCompressing() async throws {
        let h = try await ImportHarness()
        // A transcoder that fails if it is asked to compress: the original path must never call it.
        let refusing = StubTranscoder(hevc: { _, _ in throw Failure() })
        let video = try await h.pipeline(transcoder: refusing).importVideo(from: h.original, profile: spanish, quality: .original)

        try h.assertOriginalUntouched()
        XCTAssertEqual(video.videoPath, "\(video.contentHash)/video.\(h.original.pathExtension.lowercased())", "keeps its own extension")
        let stored = h.container.appending(path: "Library").appending(path: video.videoPath)
        XCTAssertEqual(try Data(contentsOf: stored), try Data(contentsOf: h.original), "byte for byte the same file")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: h.container.appending(path: "Staging").path)) ?? [], [], "staging is cleaned up")
    }

    func testTheDefaultStillCompressesToMov() async throws {
        let h = try await ImportHarness()
        let video = try await h.pipeline().importVideo(from: h.original, profile: spanish)
        XCTAssertEqual(video.videoPath, "\(video.contentHash)/video.mov")
    }

    func testCompressingIsLeftOutOfTheStepsWhenTheVideoIsKept() {
        XCTAssertEqual(ImportStage.steps(checkingLanguage: true, compressing: false).count, 6)
        XCTAssertFalse(ImportStage.steps(checkingLanguage: true, compressing: false).contains(.transcoding))
        XCTAssertEqual(ImportStage.steps(checkingLanguage: false, compressing: false).count, 5)
        let verifying = ImportStage.verifying.position(checkingLanguage: true, compressing: false)
        XCTAssertEqual(verifying.number, 5)
        XCTAssertEqual(verifying.of, 6)
        XCTAssertEqual(ImportStage.verifying.position(checkingLanguage: true).number, 6, "unchanged when compressing")
    }

    func testThePreferenceDefaultsToSmallestAndIsRemembered() {
        let defaults = UserDefaults(suiteName: "vq-\(UUID().uuidString)")!
        let preference = VideoQualityPreference(defaults: defaults)
        XCTAssertEqual(preference.quality, .smallest)
        preference.quality = .original
        XCTAssertEqual(VideoQualityPreference(defaults: defaults).quality, .original)
        preference.quality = .smallest
        XCTAssertNil(defaults.string(forKey: VideoQualityPreference.key), "the default stores nothing")
        defaults.set("nonsense", forKey: VideoQualityPreference.key)
        XCTAssertEqual(preference.quality, .smallest, "an unknown value falls back")
    }
}
