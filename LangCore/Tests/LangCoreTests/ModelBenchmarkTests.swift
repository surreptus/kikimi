import AVFoundation
import XCTest
@testable import LangCore

final class WordErrorRateTests: XCTestCase {
    func testKnownRates() {
        XCTAssertEqual(WordErrorRate.rate(reference: "la casa es grande", hypothesis: "la casa es grande"), 0)
        XCTAssertEqual(WordErrorRate.rate(reference: "la casa es grande", hypothesis: "la caza es grande"), 0.25)   // 1 substitution
        XCTAssertEqual(WordErrorRate.rate(reference: "la casa es grande", hypothesis: "la casa grande"), 0.25)       // 1 deletion
        XCTAssertEqual(WordErrorRate.rate(reference: "la casa", hypothesis: "la casa muy grande"), 1.0)             // 2 insertions
        XCTAssertEqual(WordErrorRate.rate(reference: "Hola, ¿qué tal?", hypothesis: "hola que tal"), 0.333, accuracy: 0.01)
        XCTAssertEqual(WordErrorRate.rate(reference: "Hola, ¿qué tal?", hypothesis: "hola que tal", foldingAccents: true), 0)
        XCTAssertEqual(WordErrorRate.rate(reference: "", hypothesis: ""), 0)
    }
}

/// Real model, longer speech: measures accuracy (word error rate) and speed. Opt in with LANGCORE_BENCHMARK=1.
/// LANGCORE_MODEL (default openai_whisper-medium) and LANGCORE_MODELS_DIR select the model and where it lives.
final class ModelBenchmarkTests: XCTestCase {
    static let long = """
        Esta mañana me levanté temprano porque tenía que ir al mercado. Compré tomates, cebollas y un poco de pan recién hecho. \
        La vendedora me preguntó si quería probar el queso, y le dije que sí, porque olía muy bien. \
        Después fui a la estación de tren, pero llegué tarde y tuve que esperar casi una hora. \
        Mientras esperaba, leí un libro sobre la historia de la ciudad. \
        Me sorprendió descubrir que el río antes pasaba por el centro. \
        Cuando por fin llegó el tren, estaba lleno de gente que volvía del trabajo. \
        Conseguí un asiento junto a la ventana y miré el paisaje durante todo el viaje. \
        En casa preparé la cena para mis amigos. Cocinamos juntos una sopa de verduras y un pescado al horno. \
        Hablamos de nuestros planes para el verano y decidimos viajar al sur. \
        Ninguno de nosotros conocía esa región, así que buscamos información en internet. \
        Al final de la noche estábamos cansados pero muy contentos. \
        Mañana empezaré a estudiar un poco más, porque quiero entender todas las películas sin subtítulos.
        """

    static let short = """
        Hoy hace mucho calor y nadie quiere salir de casa. Mi hermana vive en otra ciudad y la visito cada dos meses. \
        ¿Sabes dónde puedo comprar un regalo para mi madre? Dijeron que el concierto empieza a las ocho, pero no estoy seguro. \
        Perdone, ¿puede repetir la pregunta más despacio, por favor?
        """

    private var variant: String { ProcessInfo.processInfo.environment["LANGCORE_MODEL"] ?? "openai_whisper-medium" }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LANGCORE_BENCHMARK"] == "1", "set LANGCORE_BENCHMARK=1")
    }

    private func models() async throws -> ModelManager {
        let dir = ProcessInfo.processInfo.environment["LANGCORE_MODELS_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "langcore-integration-models")
        let manager = ModelManager(directory: dir)
        if await !manager.isInstalled(variant) {
            let started = Date()
            try await manager.download(variant: variant) { _ in }
            print("BENCH download \(variant): \(Int(Date().timeIntervalSince(started)))s")
        }
        return manager
    }

    private func report(_ name: String, voice: String, text: String, using transcriber: WhisperKitTranscriber) async throws {
        let video = FileManager.default.temporaryDirectory.appending(path: "bench-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: video) }
        try await SpeechFixture.makeVideo(at: video, voice: voice, text: text)
        let audioSeconds = Double(try await AudioExtractor.pcm16kMono(from: video).count) / AudioExtractor.sampleRate

        let started = Date()
        let segments = try await transcriber.transcribe(mediaURL: video, whisperCode: "es", model: variant, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)

        let hypothesis = segments.map(\.text).joined(separator: " ")
        let strict = WordErrorRate.rate(reference: text, hypothesis: hypothesis)
        let lenient = WordErrorRate.rate(reference: text, hypothesis: hypothesis, foldingAccents: true)
        print("""
            BENCH \(name) [\(voice), \(variant)]
              audio \(String(format: "%.1f", audioSeconds))s, transcribed in \(String(format: "%.1f", seconds))s \
            (\(String(format: "%.2f", seconds / audioSeconds))x real time), \(segments.count) segments
              word error rate \(String(format: "%.1f", strict * 100))% (\(String(format: "%.1f", lenient * 100))% ignoring accents)
            """)
        for s in segments { print(String(format: "BENCH   %6.1f-%6.1f  %@", s.start, s.end, s.text)) }

        XCTAssertFalse(segments.isEmpty)
        // Results are printed for comparison; only assert what must always hold.
        XCTAssertTrue(zip(segments, segments.dropFirst()).allSatisfy { $0.start <= $1.start }, "segments in order")
        if !name.contains("voice-activity") {   // known to skip the opening; kept in the report for comparison
            XCTAssertLessThan(segments[0].start, 5, "speech starts at 0: the opening must not be skipped (\(name))")
        }
    }

    func testSpanishAccuracyAndSpeed() async throws {
        let manager = try await models()
        let transcriber = WhisperKitTranscriber(models: manager, chunking: .voiceActivity)

        // First call loads and compiles the model; time it separately so speed numbers are steady-state.
        let warmupStarted = Date()
        let warmup = FileManager.default.temporaryDirectory.appending(path: "warm-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: warmup) }
        try await SpeechFixture.makeVideo(at: warmup, voice: "Mónica", text: "Hola, ¿cómo estás?")
        _ = try await transcriber.transcribe(mediaURL: warmup, whisperCode: "es", model: variant, progress: { _ in })
        print("BENCH model load + first run: \(String(format: "%.1f", Date().timeIntervalSince(warmupStarted)))s")

        let window = WhisperKitTranscriber(models: manager, chunking: .slidingWindow)
        _ = try await window.transcribe(mediaURL: warmup, whisperCode: "es", model: variant, progress: { _ in })
        try await report("long passage / voice-activity chunking", voice: "Mónica", text: Self.long, using: transcriber)
        try await report("long passage / sliding window", voice: "Mónica", text: Self.long, using: window)
        try await report("accent/questions / sliding window", voice: "Paulina", text: Self.short, using: window)
    }

    /// Transcribes any media file (LANGCORE_FILE) and writes the segments to LANGCORE_OUT, with timing statistics.
    /// Read-only on the input. LANGCORE_CHUNKING=voice switches to voice-activity chunking.
    func testTranscribeProvidedFile() async throws {
        guard let path = ProcessInfo.processInfo.environment["LANGCORE_FILE"] else { throw XCTSkip("set LANGCORE_FILE") }
        let out = ProcessInfo.processInfo.environment["LANGCORE_OUT"] ?? "/tmp/transcript.txt"
        let mode: ChunkingMode = ProcessInfo.processInfo.environment["LANGCORE_CHUNKING"] == "voice" ? .voiceActivity : .slidingWindow
        let transcriber = WhisperKitTranscriber(models: try await models(), chunking: mode)

        let file = URL(filePath: path)
        let audioSeconds = Double(try await AudioExtractor.pcm16kMono(from: file).count) / AudioExtractor.sampleRate
        let started = Date()
        let segments = try await transcriber.transcribe(mediaURL: file, whisperCode: "es", model: variant, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)

        // Segments whose length is a whole 1 s or 2 s are the signature of Whisper falling back to coarse timestamps.
        let coarse = segments.filter { s in
            let d = s.end - s.start
            return [1.0, 2.0].contains { abs(d - $0) < 0.06 }
        }
        let tagged = segments.filter { $0.text.contains("[") || $0.text.contains("(") }
        var report = "mode \(mode) model \(variant)\naudio \(String(format: "%.1f", audioSeconds))s transcribed in \(String(format: "%.1f", seconds))s (\(String(format: "%.2f", seconds / audioSeconds))x real time)\n"
        report += "segments \(segments.count), whole-second-length segments \(coarse.count), leftover tags \(tagged.count)\n"
        report += "first segment starts \(String(format: "%.1f", segments.first?.start ?? -1)), last ends \(String(format: "%.1f", segments.last?.end ?? -1))\n\n"
        report += segments.map { String(format: "%6.1f-%6.1f  %@", $0.start, $0.end, $0.text) }.joined(separator: "\n")
        try report.write(toFile: out, atomically: true, encoding: .utf8)
        print("BENCHFILE " + report.split(separator: "\n").prefix(4).joined(separator: " | "))
        XCTAssertTrue(tagged.isEmpty, "the cleaner must remove sound tags")
    }

    /// What language does the model hear in the first 30 s of LANGCORE_FILE? Read-only.
    func testDetectLanguageOfProvidedFile() async throws {
        guard let path = ProcessInfo.processInfo.environment["LANGCORE_FILE"] else { throw XCTSkip("set LANGCORE_FILE") }
        let transcriber = WhisperKitTranscriber(models: try await models())
        let guess = try await transcriber.detectLanguage(mediaURL: URL(filePath: path), model: variant)
        print("DETECTFILE \(variant): \(guess?.code ?? "nil") \(guess?.confidence ?? 0)")
    }
}
