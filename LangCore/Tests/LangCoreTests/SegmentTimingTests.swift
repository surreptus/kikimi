import Foundation
import WhisperKit
import XCTest
@testable import LangCore

/// How close Whisper's segment boundaries are to a human subtitle file's, under different settings. Opt in with
/// LANGCORE_SEGMENTS=1 and give LANGCORE_VIDEO, LANGCORE_SRT, LANGCORE_LANG, LANGCORE_MODELS_DIR (as ImportTimingTests).
/// Prints "SEGMENTS ..." lines. Only segments whose text matches a human line are compared, so the boundaries correspond.
final class SegmentTimingTests: XCTestCase {
    struct Span { var start: Double; var end: Double; var text: String }

    func testBoundaryError() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LANGCORE_SEGMENTS"] == "1", "set LANGCORE_SEGMENTS=1")
        let video = try XCTUnwrap(env["LANGCORE_VIDEO"].map { URL(filePath: $0) }, "LANGCORE_VIDEO")
        let srt = try XCTUnwrap(env["LANGCORE_SRT"].map { URL(filePath: $0) }, "LANGCORE_SRT")
        let profile = try XCTUnwrap(LanguageProfiles.profile(for: env["LANGCORE_LANG"] ?? "es"))
        let model = env["LANGCORE_MODEL"] ?? profile.defaultModel
        let modelsDir = try XCTUnwrap(env["LANGCORE_MODELS_DIR"].map { URL(filePath: $0) }, "LANGCORE_MODELS_DIR")

        let manager = ModelManager(directory: modelsDir)
        let found = await manager.installedFolder(for: model)
        let folder = try XCTUnwrap(found, "model not installed")
        let kit = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, load: true, download: false))
        let samples = try await AudioExtractor.pcm16kMono(from: video)
        let reference = (SubtitleParser.parse(try Data(contentsOf: srt), lineJoiner: profile.dictationSeparator) ?? [])
            .map { Span(start: $0.start, end: $0.end, text: $0.text) }
        print("SEGMENTS reference lines: \(reference.count), audio \(Int(Double(samples.count) / AudioExtractor.sampleRate)) s, model \(model)")

        func run(_ name: String, vad: Bool = false, words: Bool = false) async throws -> [Span] {
            let began = Date()
            let options = DecodingOptions(task: .transcribe, language: profile.whisperCode, skipSpecialTokens: true,
                                          wordTimestamps: words, chunkingStrategy: vad ? .vad : nil)
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            let spans: [Span] = results.flatMap(\.segments).map { segment in
                if words, let timings = segment.words, let first = timings.first, let last = timings.last {
                    return Span(start: Double(first.start), end: Double(last.end), text: segment.text)
                }
                return Span(start: Double(segment.start), end: Double(segment.end), text: segment.text)
            }
            print("SEGMENTS \(name): \(spans.count) segments in \(String(format: "%.1f", Date().timeIntervalSince(began))) s")
            return spans
        }

        let current = try await run("current (sliding window)")
        report("current", current, reference); cuts("current", current, samples)
        let snappedCurrent = Self.snapped(current, samples: samples)
        report("current + snapped to silence", snappedCurrent, reference); cuts("current + snapped", snappedCurrent, samples)
        let outward = Self.movedOutward(current, samples: samples)
        report("current + outward to quiet", outward, reference); cuts("current + outward to quiet", outward, samples)
        let grew = zip(current, outward).map { ($1.end - $1.start) - ($0.end - $0.start) }
        print("SEGMENTS outward to quiet: segments grow by \(String(format: "%.2f", grew.reduce(0, +) / Double(max(grew.count, 1)))) s on average, \(grew.filter { $0 > 0.4 }.count) by more than 0.4 s")
        if env["LANGCORE_QUICK"] == "1" { return }
        let vad = try await run("voice-activity chunking", vad: true)
        report("voice-activity chunking", vad, reference); cuts("voice-activity chunking", vad, samples)
        let words = try await run("word timestamps", words: true)
        report("word timestamps", words, reference); cuts("word timestamps", words, samples)
        let snappedWords = Self.snapped(words, samples: samples)
        report("word timestamps + snapped", snappedWords, reference); cuts("word timestamps + snapped", snappedWords, samples)
    }

    // MARK: Comparison

    private static func letters(_ text: String) -> [Character] { text.lowercased().filter { $0.isLetter || $0.isNumber } }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let x = letters(a), y = letters(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        for (i, c) in x.enumerated() {
            var row = [i + 1]
            for (j, d) in y.enumerated() { row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (c == d ? 0 : 1))) }
            previous = row
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    private func report(_ name: String, _ heard: [Span], _ reference: [Span]) {
        var starts: [Double] = [], ends: [Double] = []
        for span in heard {
            // The human line it overlaps most in time, kept only when the words agree.
            guard let line = reference.max(by: { overlap($0, span) < overlap($1, span) }), overlap(line, span) > 0,
                  Self.similarity(line.text, span.text) >= 0.7 else { continue }
            starts.append(span.start - line.start); ends.append(span.end - line.end)
        }
        func stats(_ label: String, _ errors: [Double]) -> String {
            guard !errors.isEmpty else { return "\(label): none" }
            let absolute = errors.map(abs).sorted()
            func q(_ p: Double) -> Double { absolute[min(absolute.count - 1, Int(p * Double(absolute.count)))] }
            let bias = errors.reduce(0, +) / Double(errors.count)
            return "\(label): median \(String(format: "%.2f", q(0.5))) s, 90th \(String(format: "%.2f", q(0.9))) s, mean \(String(format: "%+.2f", bias)) s, within 0.15 s \(Int(100 * Double(absolute.filter { $0 <= 0.15 }.count) / Double(absolute.count)))%"
        }
        print("SEGMENTS \(name) [\(starts.count) of \(heard.count) segments matched a human line] | \(stats("start", starts)) | \(stats("end", ends))")
    }

    /// Without the human file: how often a boundary lands in the middle of speech, where a clip would be cut. The sound at
    /// each boundary is compared with the loud part of its own segment; over 35% of it counts as speech under the cut.
    private func cuts(_ name: String, _ spans: [Span], _ samples: [Float]) {
        let rate = AudioExtractor.sampleRate
        func level(_ from: Double, _ to: Double) -> Float {
            let a = max(0, Int(from * rate)), b = min(samples.count, Int(to * rate))
            guard b > a else { return 0 }
            var sum: Float = 0
            for k in a..<b { sum += samples[k] * samples[k] }
            return (sum / Float(b - a)).squareRoot()
        }
        var cutStarts = 0, cutEnds = 0, counted = 0
        for span in spans where span.end - span.start > 0.8 {
            let loud = stride(from: span.start, to: span.end - 0.1, by: 0.1).map { level($0, $0 + 0.1) }.sorted()
            guard loud.count > 4 else { continue }
            let speech = loud[loud.count * 3 / 4]
            counted += 1
            if level(span.start - 0.05, span.start + 0.05) > 0.35 * speech { cutStarts += 1 }
            if level(span.end - 0.05, span.end + 0.05) > 0.35 * speech { cutEnds += 1 }
        }
        print("SEGMENTS \(name) | cut through speech: start \(100 * cutStarts / max(counted, 1))%, end \(100 * cutEnds / max(counted, 1))% of \(counted) segments")
    }

    private func overlap(_ a: Span, _ b: Span) -> Double { max(0, min(a.end, b.end) - max(a.start, b.start)) }

    // MARK: Moving outward

    /// A boundary that lands in loud speech moves out (a start earlier, an end later) to the quietest moment within half
    /// a second, never into the neighbouring segment. A boundary already in a quiet place stays.
    static func movedOutward(_ spans: [Span], samples: [Float], reach: Double = 0.5) -> [Span] {
        let rate = AudioExtractor.sampleRate
        func level(_ from: Double, _ to: Double) -> Float {
            let a = max(0, Int(from * rate)), b = min(samples.count, Int(to * rate))
            guard b > a else { return 0 }
            var sum: Float = 0
            for k in a..<b { sum += samples[k] * samples[k] }
            return (sum / Float(b - a)).squareRoot()
        }
        func quietest(_ from: Double, _ to: Double) -> Double {
            var best = from, bestLevel = Float.greatestFiniteMagnitude, t = from
            while t < to {
                let l = level(t, t + 0.03)
                if l < bestLevel { bestLevel = l; best = t + 0.015 }
                t += 0.01
            }
            return best
        }
        return spans.enumerated().map { index, span in
            var s = span
            guard span.end - span.start > 0.8 else { return span }
            let loud = stride(from: span.start, to: span.end - 0.1, by: 0.1).map { level($0, $0 + 0.1) }.sorted()
            guard loud.count > 4 else { return span }
            let speech = loud[loud.count * 3 / 4]
            let before = index > 0 ? spans[index - 1].end : 0
            let after = index + 1 < spans.count ? spans[index + 1].start : Double(samples.count) / rate
            if level(span.start - 0.05, span.start + 0.05) > 0.35 * speech {
                s.start = quietest(max(before, span.start - reach), span.start)
            }
            if level(span.end - 0.05, span.end + 0.05) > 0.35 * speech {
                s.end = quietest(span.end, min(after, span.end + reach))
            }
            return s
        }
    }

    // MARK: Snapping to silence

    /// Each boundary moved to the edge of the speech nearest it: a start to where the sound begins, an end to where it
    /// stops, looking a little either side. A boundary already inside a pause is left alone.
    static func snapped(_ spans: [Span], samples: [Float], window: Double = 0.4) -> [Span] {
        let rate = AudioExtractor.sampleRate, hop = Int(rate * 0.01)
        let frames: [Float] = stride(from: 0, to: samples.count - hop, by: hop).map { i in
            var sum: Float = 0
            for k in i..<(i + hop) { sum += samples[k] * samples[k] }
            return (sum / Float(hop)).squareRoot()
        }
        func frame(_ t: Double) -> Int { min(max(0, Int(t * 100)), frames.count - 1) }
        func threshold(_ lo: Int, _ hi: Int) -> Float {
            let sorted = frames[lo...hi].sorted()
            let floor = sorted[sorted.count / 10], peak = sorted[sorted.count * 95 / 100]
            return floor + 0.2 * (peak - floor)
        }
        return spans.map { span in
            var s = span
            let a = frame(span.start - window), b = frame(span.start + window)
            if b > a {
                let t = threshold(a, b)
                // Walk back from where speech is found to where it starts.
                if let hit = (frame(span.start)...b).first(where: { frames[$0] >= t }) {
                    var i = hit
                    while i > a, frames[i - 1] >= t { i -= 1 }
                    s.start = Double(i) / 100
                }
            }
            let c = frame(span.end - window), d = frame(span.end + window)
            if d > c {
                let t = threshold(c, d)
                if let hit = stride(from: frame(span.end), through: c, by: -1).first(where: { frames[$0] >= t }) {
                    var i = hit
                    while i < d, frames[i + 1] >= t { i += 1 }
                    s.end = Double(i + 1) / 100
                }
            }
            return s.end > s.start ? s : span
        }
    }
}
