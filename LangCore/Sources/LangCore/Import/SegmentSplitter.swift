import Foundation

/// A word as the speech model heard it, with when it was said.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

/// Whisper breaks at pauses, so a long run of speech can come back as one long unit (6 of 80 were over 8 seconds in a test on a
/// 5-minute video): too much to read, hear again or loop. This cuts such a unit at its longest pause between words, and each part
/// again while it is still too long. Only the cut is new: the words are Whisper's, and so are the times (a part starts at its
/// first word and ends at its last, the outer ends staying where Whisper put them).
public enum SegmentSplitter {
    /// What a part must keep on each side of a cut, so no cut leaves a fragment.
    static let shortest = 1.0

    public static func split(_ segment: TranscriptSegment, words: [TimedWord], maxSeconds: Double) -> [TranscriptSegment] {
        guard segment.end - segment.start > maxSeconds, words.count >= 4,
              letters(words.map(\.text).joined()) == letters(segment.text) else { return [segment] }
        var parts: [Range<Int>] = []
        cut(words, 0..<words.count, maxSeconds: maxSeconds, into: &parts)
        guard parts.count > 1 else { return [segment] }
        return parts.enumerated().map { index, range in
            let text = words[range].map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            let start = index == 0 ? segment.start : words[range.lowerBound].start
            let end = index == parts.count - 1 ? segment.end : words[range.upperBound - 1].end
            return TranscriptSegment(start: start, end: end, text: text)
        }
    }

    /// The letters and numbers, so words that carry their own spaces and marks compare with the segment's text.
    private static func letters(_ text: String) -> String { String(text.filter { $0.isLetter || $0.isNumber }) }

    private static func cut(_ words: [TimedWord], _ range: Range<Int>, maxSeconds: Double, into parts: inout [Range<Int>]) {
        let start = words[range.lowerBound].start, end = words[range.upperBound - 1].end
        guard end - start > maxSeconds, range.count >= 4 else { parts.append(range); return }
        var best: (index: Int, gap: Double)?
        for i in (range.lowerBound + 1)..<range.upperBound {
            guard words[i - 1].end - start >= shortest, end - words[i].start >= shortest else { continue }   // speech on each side, not the pause
            let gap = words[i].start - words[i - 1].end
            if best == nil || gap > best!.gap { best = (i, gap) }
        }
        guard let cutAt = best?.index else { parts.append(range); return }
        cut(words, range.lowerBound..<cutAt, maxSeconds: maxSeconds, into: &parts)
        cut(words, cutAt..<range.upperBound, maxSeconds: maxSeconds, into: &parts)
    }
}
