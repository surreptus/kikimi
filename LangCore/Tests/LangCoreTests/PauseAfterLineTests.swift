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

    func testEditedLineReplacesThatLineAndTimingFollows() async throws {
        let c = try await controller()
        var edited = c.lines[1]
        edited.text = "tres"
        c.replaceLine(at: 1, with: edited)
        XCTAssertEqual(c.lines.map(\.text), ["uno", "tres"])

        edited.startTime = 0.1; edited.endTime = 0.4      // moved before the first line: the order follows the times
        c.replaceLine(at: 1, with: edited)
        XCTAssertEqual(c.lines.map(\.text), ["tres", "uno"])
        c.replaceLine(at: 9, with: edited)               // out of range: ignored
        XCTAssertEqual(c.lines.count, 2)
        c.stop()
    }

    func testLoopingRepeatsTheLineAndAtTheChosenSpeed() async throws {
        let c = try await controller()
        c.loopSpeed = 1
        await c.seek(to: 0.6, play: true)
        await c.toggleLoop()
        XCTAssertEqual(c.loopingIndex, 0)

        var times: [Double] = []
        for _ in 0..<80 { try await Task.sleep(for: .milliseconds(40)); times.append(c.player.currentTime().seconds) }
        XCTAssertLessThan(times.max() ?? 99, 1.9, "it never gets past the first line's end")
        let wraps = zip(times, times.dropFirst()).filter { $0 - $1 > 0.5 }.count
        XCTAssertGreaterThanOrEqual(wraps, 1, "it went back to the start at least once")

        c.loopSpeed = 0.5
        XCTAssertEqual(c.player.rate, 0.5, accuracy: 0.01, "slower while looping")
        c.stopLooping()
        XCTAssertEqual(c.player.rate, 1, accuracy: 0.01, "normal again afterwards")
        XCTAssertNil(c.loopingIndex)
        c.stop()
    }

    func testGoingSomewhereElseEndsTheLoop() async throws {
        let c = try await controller()
        await c.seek(to: 0.6, play: true)
        await c.toggleLoop()
        await c.seek(toLine: 1)
        XCTAssertNil(c.loopingIndex)
        c.stop()
    }

    func testAPreviewedRangePlaysOnceThenPauses() async throws {
        let c = try await controller()
        await c.playRange(from: 0.5, to: 1.3)
        try await Task.sleep(for: .milliseconds(300))
        try await waitUntilPaused(c)
        XCTAssertEqual(c.player.currentTime().seconds, 1.3, accuracy: 0.35)
        c.stop()
    }
}

@MainActor
final class ListeningTimeTests: XCTestCase {
    func testTimeSpentPlayingIsReportedAndPausedTimeIsNot() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "listen-\(UUID().uuidString).mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url, seconds: 6)
        let c = PlaybackController(url: url, lines: [])
        c.player.isMuted = true
        var reported: TimeInterval = 0
        c.onListened = { reported += $0 }

        await c.seek(to: 0.2, play: true)
        try await Task.sleep(for: .milliseconds(1800))
        c.pause()
        try await Task.sleep(for: .milliseconds(1500))   // paused: this must not count
        c.stop()
        XCTAssertGreaterThan(reported, 1.0, "about the 1.8 seconds it played")
        XCTAssertLessThan(reported, 2.4, "not the pause as well")
    }
}
