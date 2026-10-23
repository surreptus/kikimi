import AVFoundation
import XCTest
@testable import LangCore

@MainActor
final class PlaybackSpeedTests: XCTestCase {
    func testSpeedAppliesToPlaybackNowAndLater() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "speed-\(UUID().uuidString).mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url, seconds: 3)
        let controller = PlaybackController(url: url, lines: [])
        controller.player.isMuted = true   // the fixture's audio is a tone
        defer { controller.stop() }

        XCTAssertEqual(controller.speed, 1)
        controller.speed = 1.5
        XCTAssertEqual(controller.player.defaultRate, 1.5)
        controller.play()
        XCTAssertEqual(controller.player.rate, 1.5, "starts at the chosen speed")
        controller.speed = 0.75
        XCTAssertEqual(controller.player.rate, 0.75, "changing speed while playing takes effect at once")
        controller.pause()
        controller.speed = 1.25
        XCTAssertEqual(controller.player.rate, 0, "changing speed while paused doesn't start playback")
        controller.play()
        XCTAssertEqual(controller.player.rate, 1.25)
    }
}
