import Foundation

/// Removes what Whisper adds that isn't speech: sound tags like `[AUDIO_EN_BLANCO]` or `(música)`, music
/// symbols, empty segments, and timestamps that run past the end of the audio.
public enum TranscriptCleaner {
    private static let tags = try! NSRegularExpression(pattern: #"\[[^\]]*\]|\([^)]*\)|[♪♫♬]+"#)

    public static func clean(_ segments: [TranscriptSegment], audioDuration: Double? = nil) -> [TranscriptSegment] {
        segments.compactMap { segment in
            let range = NSRange(segment.text.startIndex..., in: segment.text)
            let stripped = tags.stringByReplacingMatches(in: segment.text, range: range, withTemplate: " ")
            let text = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }

            var cleaned = TranscriptSegment(start: max(0, segment.start), end: segment.end, text: text)
            if let duration = audioDuration {
                guard cleaned.start < duration else { return nil }
                cleaned.end = min(cleaned.end, duration)
            }
            return cleaned.end > cleaned.start ? cleaned : nil
        }
    }
}
