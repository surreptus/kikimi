import AVFoundation
import XCTest
@testable import LangCore

final class MediaCheckTests: XCTestCase {
    private func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "mediacheck-\(UUID().uuidString)-\(name)")
    }

    func testAVideoIsFine() async throws {
        let url = temp("clip.mov"); defer { try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url)
        let problem = await MediaCheck.problem(with: url)
        XCTAssertNil(problem)
    }

    func testAFileMacOSCannotOpenIsRefusedWithTheFormatNamed() async throws {
        // Not a real WebM, but what matters is that macOS cannot open it, as it cannot open real ones.
        let url = temp("talk.webm"); defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a video".utf8).write(to: url)
        let problem = await MediaCheck.problem(with: url)
        XCTAssertEqual(problem, .cannotOpen)
        XCTAssertTrue(problem?.message(for: url).contains("WebM or MKV") == true)
        XCTAssertTrue(problem?.message(for: url).contains(url.lastPathComponent) == true)
    }

    func testAFileThatCannotBeReadHereIsNotCalledDamaged() async throws {
        // A sandboxed app without a file's security scope cannot read it, and a good file would then look damaged.
        let url = temp("locked.mp4"); defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path); try? FileManager.default.removeItem(at: url) }
        try await FixtureVideo.make(at: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let problem = await MediaCheck.problem(with: url)
        XCTAssertNil(problem, "left for the import, which holds the scope and says what is wrong")
    }

    func testADamagedFileOfAnotherKindDoesNotBlameWebM() {
        let url = URL(filePath: "/tmp/film.mp4")
        XCTAssertFalse(MediaProblem.cannotOpen.message(for: url).contains("WebM"))
    }

    func testAnAudioFileIsToldItHasNoVideo() async throws {
        let url = temp("tone.wav"); defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        try file.write(from: buffer)
        let problem = await MediaCheck.problem(with: url)
        XCTAssertEqual(problem, .noVideo)
    }
}
