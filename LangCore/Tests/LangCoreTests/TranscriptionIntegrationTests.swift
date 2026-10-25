import GRDB
import XCTest
@testable import LangCore

/// Real WhisperKit, real model download, real AVFoundation. Opt in with LANGCORE_INTEGRATION=1.
/// Downloads the tiny model (once, cached in the temp directory) from Hugging Face.
final class TranscriptionIntegrationTests: XCTestCase {
    /// Tiny by default (small download); LANGCORE_MODEL / LANGCORE_MODELS_DIR select another, e.g. medium.
    static let model = ProcessInfo.processInfo.environment["LANGCORE_MODEL"] ?? "openai_whisper-tiny"
    static let modelsDirectory = ProcessInfo.processInfo.environment["LANGCORE_MODELS_DIR"].map { URL(filePath: $0) }
        ?? FileManager.default.temporaryDirectory.appending(path: "langcore-integration-models")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LANGCORE_INTEGRATION"] == "1",
                          "set LANGCORE_INTEGRATION=1 to run")
    }

    private func installedModels() async throws -> ModelManager {
        let models = ModelManager(directory: Self.modelsDirectory)
        if await !models.isInstalled(Self.model) {
            let started = Date()
            try await models.download(variant: Self.model) { _ in }
            print("model download took \(Date().timeIntervalSince(started))s")
        }
        let installed = await models.isInstalled(Self.model)
        XCTAssertTrue(installed)
        return models
    }

    private func speechVideo(voice: String, text: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "speech-\(UUID().uuidString).mov")
        try await SpeechFixture.makeVideo(at: url, voice: voice, text: text)
        return url
    }

    func testSpanishTranscription() async throws {
        let models = try await installedModels()
        let video = try await speechVideo(voice: "Mónica", text: "La casa es grande. Corremos rápidamente a la escuela.")
        defer { try? FileManager.default.removeItem(at: video) }

        let started = Date()
        let segments = try await WhisperKitTranscriber(models: models).transcribe(
            mediaURL: video, whisperCode: "es", model: Self.model, progress: { _ in })
        print("es transcription took \(Date().timeIntervalSince(started))s:", segments)

        XCTAssertFalse(segments.isEmpty)
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("casa"), text)
        XCTAssertTrue(segments.allSatisfy { $0.start >= 0 && $0.end > $0.start })
    }

    func testJapaneseTranscriptionProducesJapaneseText() async throws {
        let models = try await installedModels()
        let video = try await speechVideo(voice: "Kyoko", text: "昨日は友達と新しいレストランへ行きました。")
        defer { try? FileManager.default.removeItem(at: video) }

        let segments = try await WhisperKitTranscriber(models: models).transcribe(
            mediaURL: video, whisperCode: "ja", model: Self.model, progress: { _ in })
        print("ja transcription (tiny model):", segments)

        XCTAssertFalse(segments.isEmpty)
        let text = segments.map(\.text).joined()
        XCTAssertTrue(text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }, text)
    }

    func testFullImportWithRealTranscriberAndTranscoder() async throws {
        let models = try await installedModels()
        let video = try await speechVideo(voice: "Mónica", text: "La casa es grande. Corremos rápidamente a la escuela.")
        defer { try? FileManager.default.removeItem(at: video) }

        let root = FileManager.default.temporaryDirectory.appending(path: "e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LangDatabase()
        let pipeline = ImportPipeline(database: database, root: root, transcriber: WhisperKitTranscriber(models: models))

        let before = try ImportHarness.snapshot(of: video)
        let saved = try await pipeline.importVideo(from: video, profile: SpanishProfile(), model: Self.model)
        XCTAssertEqual(try ImportHarness.snapshot(of: video), before, "original must be untouched")

        let library = root.appending(path: "Library")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.appending(path: saved.videoPath).path))
        XCTAssertNil(saved.audioPath)

        let lemmas = try await database.writer.read { try String.fetchSet($0, sql: "SELECT lemma FROM words") }
        let lines = try await database.writer.read { try String.fetchAll($0, sql: "SELECT text FROM subtitles ORDER BY idx") }
        print("subtitles:", lines, "lemmas:", lemmas.sorted())
        XCTAssertTrue(lemmas.contains("casa"), "\(lemmas)")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Staging").path), [])
    }

    /// Japanese speech is reliably told apart. Synthesized Spanish is NOT asserted: the robotic `say` voice is
    /// often called English even by medium, while real Spanish speech is detected correctly (checked on a real vlog:
    /// es, 99.7%; see ModelBenchmarkTests.testDetectLanguageOfProvidedFile).
    func testLanguageDetectionRecognisesJapanese() async throws {
        let models = try await installedModels()
        let transcriber = WhisperKitTranscriber(models: models)
        let video = try await speechVideo(voice: "Kyoko", text: "昨日は友達と新しいレストランへ行きました。とても美味しかったです。")
        defer { try? FileManager.default.removeItem(at: video) }
        let guess = try await transcriber.detectLanguage(mediaURL: video, model: Self.model)
        XCTAssertEqual(guess?.code, "ja")
        XCTAssertGreaterThan(guess?.confidence ?? 0, 0.6, "confident enough to act on")

        let spanish = try await speechVideo(voice: "Mónica", text: "La casa es grande y mi madre vive en otra ciudad con mis hermanos.")
        defer { try? FileManager.default.removeItem(at: spanish) }
        let other = try await transcriber.detectLanguage(mediaURL: spanish, model: Self.model)
        print("DETECT (informational) synthesized Spanish -> \(other?.code ?? "nil") \(other?.confidence ?? 0)")
    }

    func testPipelineStopsAJapaneseFileImportedAsSpanish() async throws {
        let models = try await installedModels()
        let video = try await speechVideo(voice: "Kyoko", text: "昨日は友達と新しいレストランへ行きました。とても美味しかったです。")
        defer { try? FileManager.default.removeItem(at: video) }
        let root = FileManager.default.temporaryDirectory.appending(path: "lang-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LangDatabase()
        let pipeline = ImportPipeline(database: database, root: root, transcriber: WhisperKitTranscriber(models: models))

        let before = try ImportHarness.snapshot(of: video)
        do {
            _ = try await pipeline.importVideo(from: video, profile: SpanishProfile(), model: Self.model)
            XCTFail("expected a language mismatch")
        } catch ImportError.languageMismatch(let detected, let chosen, _) {
            XCTAssertEqual(detected, "ja")
            XCTAssertEqual(chosen, "es")
        }
        XCTAssertEqual(try ImportHarness.snapshot(of: video), before)
        let count = try await database.libraryVideos().count
        XCTAssertEqual(count, 0)
    }
}
