import AVFoundation
import XCTest
@testable import LangCore

@MainActor
final class PauseAfterLineTests: XCTestCase {
    private func controller() async throws -> PlaybackController {
        let url = FileManager.default.temporaryDirectory.appending(path: "pause-\(UUID().uuidString).mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url, seconds: 5)
        let lines = [
            Subtitle(videoId: 1, idx: 0, startTime: 0.5, endTime: 1.5, text: "uno"),
            Subtitle(videoId: 1, idx: 1, startTime: 2.5, endTime: 3.5, text: "dos"),
        ]
        let c = PlaybackController(url: url, lines: lines)
        c.player.isMuted = true
        return c
    }

    private func waitUntilPaused(_ c: PlaybackController, timeout: Double = 5) async throws {
        for _ in 0..<Int(timeout * 20) {
            try await Task.sleep(for: .milliseconds(50))
            if c.player.rate == 0 { return }
        }
    }

    func testPausesAtTheEndOfEachLineWhenOn() async throws {
        let c = try await controller()
        c.pausesAfterLines = true
        await c.seek(to: 0.3, play: true)
        try await waitUntilPaused(c)
        XCTAssertEqual(c.player.rate, 0, "it stopped by itself")
        XCTAssertEqual(c.player.currentTime().seconds, 1.5, accuracy: 0.35, "at the end of the first line")
        XCTAssertFalse(c.isPlaying)

        c.play()                                  // carry on: the next line ends the next pause
        try await Task.sleep(for: .milliseconds(300))
        try await waitUntilPaused(c)
        XCTAssertEqual(c.player.currentTime().seconds, 3.5, accuracy: 0.35, "at the end of the second line")
        c.stop()
    }

    func testPlaysStraightThroughWhenOff() async throws {
        let c = try await controller()
        await c.seek(to: 0.3, play: true)
        try await Task.sleep(for: .milliseconds(1800))   // past the first line's end at 1.5
        XCTAssertNotEqual(c.player.rate, 0, "no pause when the setting is off")
        c.stop()
    }

    func testEditedTextReplacesOnlyThatLine() async throws {
        let c = try await controller()
        c.replaceText(at: 1, with: "tres")
        XCTAssertEqual(c.lines.map(\.text), ["uno", "tres"])
        XCTAssertEqual(c.lines.map(\.startTime), [0.5, 2.5], "timing is untouched")
        c.replaceText(at: 9, with: "no")   // out of range: ignored
        XCTAssertEqual(c.lines.count, 2)
        c.stop()
    }
}
