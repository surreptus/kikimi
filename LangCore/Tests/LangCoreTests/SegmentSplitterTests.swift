import XCTest
@testable import LangCore

final class SegmentSplitterTests: XCTestCase {
    /// Words at 0.4 s each, with the pauses given before each word (seconds), so the test says where the pauses are.
    private func words(_ texts: [String], pauses: [Double], from start: Double = 0, each: Double = 0.4) -> [TimedWord] {
        var t = start
        return zip(texts, pauses).map { text, pause in
            t += pause
            defer { t += each }
            return TimedWord(text: text, start: t, end: t + each)
        }
    }

    private func segment(_ words: [TimedWord]) -> TranscriptSegment {
        TranscriptSegment(start: words.first!.start, end: words.last!.end, text: words.map(\.text).joined().trimmingCharacters(in: .whitespaces))
    }

    func testALongLineIsCutAtItsLongestPause() {
        // 16 words, a 0.2 s pause everywhere but 0.9 s before the ninth: about 10 s in all.
        let ws = words((1...16).map { "語\($0)" }, pauses: [0] + Array(repeating: 0.2, count: 7) + [0.9] + Array(repeating: 0.2, count: 7))
        let whole = segment(ws)
        XCTAssertGreaterThan(whole.end - whole.start, 6.5)
        let parts = SegmentSplitter.split(whole, words: ws, maxSeconds: 6.5)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].text, (1...8).map { "語\($0)" }.joined())
        XCTAssertEqual(parts[1].text, (9...16).map { "語\($0)" }.joined())
        XCTAssertEqual(parts[0].start, whole.start, "the outer ends stay where Whisper put them")
        XCTAssertEqual(parts[1].end, whole.end)
        XCTAssertEqual(parts[0].end, ws[7].end, "a part ends at its last word")
        XCTAssertEqual(parts[1].start, ws[8].start, "and the next starts at its first")
    }

    func testAShortLineIsLeftAlone() {
        let ws = words(["こんにちは", "皆さん", "今日は", "元気", "ですか"], pauses: [0, 0.2, 0.2, 0.2, 0.2])
        let whole = segment(ws)
        XCTAssertEqual(SegmentSplitter.split(whole, words: ws, maxSeconds: 6.5), [whole])
    }

    func testEachPartIsCutAgainWhileItIsTooLong() {
        let ws = words((1...30).map { "w\($0)" }, pauses: [0] + (1..<30).map { $0 % 10 == 0 ? 0.8 : 0.15 })
        let whole = segment(ws)
        let parts = SegmentSplitter.split(whole, words: ws, maxSeconds: 6.5)
        XCTAssertGreaterThan(parts.count, 2)
        for p in parts { XCTAssertLessThanOrEqual(p.end - p.start, 6.5 + 0.8, "each part is about the limit or less: \(p)") }
        XCTAssertEqual(parts.map(\.text).joined(), ws.map(\.text).joined(), "no word is lost, changed or moved")
        XCTAssertEqual(zip(parts, parts.dropFirst()).filter { $0.end > $1.start }.count, 0, "parts do not overlap")
    }

    func testNoCutLeavesAFragment() {
        // The only big pause is right after the first word: cutting there would leave 0.4 s.
        let ws = words((1...14).map { "w\($0)" }, pauses: [0, 1.5] + Array(repeating: 0.1, count: 12))
        let parts = SegmentSplitter.split(segment(ws), words: ws, maxSeconds: 6.5)
        for p in parts { XCTAssertGreaterThanOrEqual(p.end - p.start, 1.0, "\(p)") }
    }

    func testWordsThatDoNotMatchTheTextAreNotUsed() {
        let ws = words((1...16).map { "語\($0)" }, pauses: [0] + Array(repeating: 0.5, count: 15))
        var whole = segment(ws); whole.text = "まったく違う文章がここにあります、それは単語と合いません"
        XCTAssertEqual(SegmentSplitter.split(whole, words: ws, maxSeconds: 6.5), [whole])
    }

    func testSpacedLanguagesKeepTheirSpaces() {
        let texts = [" Ayer", " fui", " al", " mercado", " con", " mi", " madre", " y", " compramos", " muchas", " frutas", " frescas", " para", " la", " cena", " de", " hoy"]
        let ws = words(texts, pauses: [0] + Array(repeating: 0.2, count: 8) + [0.9] + Array(repeating: 0.2, count: 7), each: 0.5)
        let whole = segment(ws)
        let parts = SegmentSplitter.split(whole, words: ws, maxSeconds: 6.5)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].text, "Ayer fui al mercado con mi madre y compramos")
        XCTAssertEqual(parts[1].text, "muchas frutas frescas para la cena de hoy")
    }

    func testTheProfileSetsTheLimit() {
        for profile in LanguageProfiles.all { XCTAssertEqual(profile.maxSegmentSeconds, 6.5, accuracy: 0.001, profile.code) }
        XCTAssertEqual(LanguageProfiles.profile(forWhisperCode: "ja")?.code, "ja")
    }
}
