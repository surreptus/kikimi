import CryptoKit
import Foundation
import GRDB
import XCTest
@testable import LangCore

struct StubTranscriber: Transcriber {
    var result: Result<[TranscriptSegment], Error>
    /// What language detection reports; nil means "can't tell". `detectionFails` makes it throw instead.
    var detected: LanguageGuess?
    var detectionFails = false

    func detectLanguage(mediaURL: URL, model: String) async throws -> LanguageGuess? {
        if detectionFails { throw Failure() }
        return detected
    }
    func transcribe(
        mediaURL: URL, whisperCode: String, model: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] { try result.get() }
}

/// Real AVFoundation by default; individual steps can be replaced to inject failures.
struct StubTranscoder: MediaTranscoder {
    var hevc: (@Sendable (URL, URL) async throws -> Void)?
    var aac: (@Sendable (URL, URL) async throws -> Void)?
    private let real = AVFoundationTranscoder()

    func compactVideo(source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        if let hevc { try await hevc(source, destination) }
        else { try await real.compactVideo(source: source, destination: destination, progress: progress) }
    }

    func extractAAC(source: URL, destination: URL) async throws {
        if let aac { try await aac(source, destination) }
        else { try await real.extractAAC(source: source, destination: destination) }
    }
}

struct Failure: Error {}

let spanishSegments = [
    TranscriptSegment(start: 0, end: 1, text: "La casa es grande."),
    TranscriptSegment(start: 1, end: 2, text: "Corremos rápidamente a la casa."),
]

/// A throwaway container + originals folder, with a snapshot of the original to prove it is never touched.
final class ImportHarness {
    let dir: URL
    let container: URL
    let original: URL
    let database: LangDatabase
    private let snapshot: Snapshot

    struct Snapshot: Equatable {
        let digest: String
        let modified: Date
        let size: Int
    }

    static func snapshot(of url: URL) throws -> Snapshot {
        let data = try Data(contentsOf: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return Snapshot(
            digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            modified: attrs[.modificationDate] as! Date, size: data.count)
    }

    init(seconds: Int = 2) async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "langcore-\(UUID().uuidString)")
        container = dir.appending(path: "container")
        let originals = dir.appending(path: "originals")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        original = originals.appending(path: "clip.mov")
        try await FixtureVideo.make(at: original, seconds: seconds)
        snapshot = try Self.snapshot(of: original)
        database = try LangDatabase()
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func pipeline(
        transcriber: StubTranscriber = StubTranscriber(result: .success(spanishSegments)),
        transcoder: StubTranscoder = StubTranscoder()
    ) -> ImportPipeline {
        ImportPipeline(database: database, root: container, transcriber: transcriber, transcoder: transcoder)
    }

    func assertOriginalUntouched(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Self.snapshot(of: original), snapshot, "original changed", file: file, line: line)
    }

    private func contents(_ name: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: container.appending(path: name).path)) ?? []
    }

    func assertNothingLeft(file: StaticString = #filePath, line: UInt = #line) async throws {
        XCTAssertEqual(contents("Staging"), [], "staging not cleaned", file: file, line: line)
        XCTAssertEqual(contents("Library"), [], "library not cleaned", file: file, line: line)
        try await database.writer.read { db in
            for table in ["videos", "subtitles", "words", "occurrences"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0, table,
                               file: file, line: line)
            }
        }
    }
}
