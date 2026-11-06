import AVFoundation
import XCTest
@testable import LangCore

/// Times each step of a real import: opt in with LANGCORE_TIMING=1, and give LANGCORE_VIDEO (a file), LANGCORE_LANG (es, ja...),
/// LANGCORE_MODELS_DIR (a folder holding `models/` and `installed.json`, as the app's does) and optionally LANGCORE_MODEL.
/// Prints "TIMING ..." lines. Nothing is written outside a temporary folder.
final class ImportTimingTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var current: (stage: ImportStage, start: Date)?
        private(set) var spans: [(ImportStage, TimeInterval)] = []
        func note(_ stage: ImportStage) {
            lock.lock(); defer { lock.unlock() }
            let now = Date()
            if let current, current.stage != stage { spans.append((current.stage, now.timeIntervalSince(current.start))) }
            if current?.stage != stage { current = (stage, now) }
        }
        func finish() {
            lock.lock(); defer { lock.unlock() }
            if let current { spans.append((current.stage, Date().timeIntervalSince(current.start))) }
            current = nil
        }
    }

    func testStageTimes() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LANGCORE_TIMING"] == "1", "set LANGCORE_TIMING=1")
        let video = try XCTUnwrap(env["LANGCORE_VIDEO"].map { URL(filePath: $0) }, "LANGCORE_VIDEO")
        let profile = try XCTUnwrap(LanguageProfiles.profile(for: env["LANGCORE_LANG"] ?? "es"))
        let model = env["LANGCORE_MODEL"] ?? profile.defaultModel
        let modelsDir = try XCTUnwrap(env["LANGCORE_MODELS_DIR"].map { URL(filePath: $0) }, "LANGCORE_MODELS_DIR")

        let root = FileManager.default.temporaryDirectory.appending(path: "langcore-timing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LangDatabase()
        let manager = ModelManager(directory: modelsDir)
        if env["LANGCORE_DOWNLOAD"] == "1", await !manager.isInstalled(model) {
            let began = Date()
            try await manager.download(variant: model) { _ in }
            print("TIMING download \(model): \(Int(Date().timeIntervalSince(began))) s")
        }
        let transcriber = WhisperKitTranscriber(models: manager)
        let pipeline = ImportPipeline(database: db, root: root, transcriber: transcriber)

        let seconds = (try? await AVURLAsset(url: video).load(.duration).seconds) ?? 0
        let clock = Clock()
        let started = Date()
        let saved = try await pipeline.importVideo(from: video, profile: profile, model: model, checkLanguage: true) {
            clock.note($0.stage)
        }
        clock.finish()
        let total = Date().timeIntervalSince(started)
        print("TIMING video \(Int(seconds)) s, model \(model), total \(String(format: "%.1f", total)) s (\(String(format: "%.1f", seconds / max(total, 0.1)))x real time)")
        for (stage, time) in clock.spans { print("TIMING \(stage.rawValue): \(String(format: "%.1f", time)) s") }

        // With LANGCORE_SRT (a human subtitle file for the same video), how far Whisper's text is from it.
        if let srt = env["LANGCORE_SRT"].map({ URL(filePath: $0) }), let data = try? Data(contentsOf: srt) {
            let reference = SubtitleParser.parse(data, lineJoiner: profile.dictationSeparator) ?? []
            let heard = try await db.subtitles(videoID: saved.id!)
            func letters(_ text: String) -> [Character] { text.lowercased().filter { $0.isLetter || $0.isNumber } }
            let ref = reference.flatMap { letters($0.text) }, hyp = heard.flatMap { letters($0.text) }
            let distance = Self.editDistance(ref, hyp)
            print("TIMING accuracy: \(String(format: "%.1f", 100 * Double(distance) / Double(max(ref.count, 1))))% of characters differ (\(distance) of \(ref.count)); \(reference.count) reference lines, \(heard.count) heard")
            // Lines side by side, by time, for reading.
            for line in reference {
                let overlapping = heard.filter { $0.startTime < line.end && $0.endTime > line.start }.map(\.text).joined()
                if letters(line.text) != letters(overlapping) { print("DIFF [\(Int(line.start))s] SRT: \(line.text)\n          ASR: \(overlapping)") }
            }
        }
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1]
            for (j, y) in b.enumerated() { row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (x == y ? 0 : 1))) }
            previous = row
        }
        return previous[b.count]
    }
}
