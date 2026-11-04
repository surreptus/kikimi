import Foundation
import NaturalLanguage

/// Reads a subtitle file (SubRip .srt or WebVTT .vtt) into the same segments that transcribing produces, so a video
/// that already has good subtitles is imported without the speech model.
public enum SubtitleParser {
    public static let fileExtensions: Set<String> = ["srt", "vtt"]

    /// The text of a subtitle file, or nil if it can't be read as text. UTF-8 (with or without a byte order mark) and
    /// UTF-16 are read as they are; anything else is left to the system to recognise, which covers files saved by older
    /// tools in a Japanese or Western encoding.
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var converted: NSString?
        let encoding = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        return encoding == 0 ? nil : converted as String?
    }

    /// The cues of a file, in order of start time, with markup removed. `lineJoiner` goes between the lines of one cue:
    /// a space, or nothing for a language written without spaces. Sound descriptions such as "[Music]" are left in;
    /// `TranscriptCleaner` removes them, as it does for a transcript.
    public static func parse(_ text: String, lineJoiner: String = " ") -> [TranscriptSegment] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cues: [TranscriptSegment] = []
        var index = 0
        while index < lines.count {
            guard let (start, end) = timing(in: lines[index]) else { index += 1; continue }
            index += 1
            var body: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                // A file with no blank line between cues: the next cue's number and timing end this one.
                if timing(in: lines[index]) != nil { break }
                if lines[index].allSatisfy(\.isNumber), index + 1 < lines.count, timing(in: lines[index + 1]) != nil { break }
                body.append(lines[index])
                index += 1
            }
            let joined = body.map(strip).filter { !$0.isEmpty }.joined(separator: lineJoiner)
            if !joined.isEmpty, end > start { cues.append(TranscriptSegment(start: start, end: end, text: joined)) }
        }
        return cues.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
    }

    public static func parse(_ data: Data, lineJoiner: String = " ") -> [TranscriptSegment]? {
        decode(data).map { parse($0, lineJoiner: lineJoiner) }
    }

    // MARK: Pieces

    /// "00:01:02,500 --> 00:01:04,000" (SubRip) or "01:02.500 --> 01:04.000 align:start" (WebVTT).
    private static let timingLine = try! NSRegularExpression(
        pattern: #"^\s*((?:\d+:)?\d{1,2}:\d{1,2}[.,]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{1,2}[.,]\d{1,3})"#)

    private static func timing(in line: String) -> (Double, Double)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = timingLine.firstMatch(in: line, range: range),
              let first = Range(match.range(at: 1), in: line), let second = Range(match.range(at: 2), in: line),
              let start = seconds(line[first]), let end = seconds(line[second]) else { return nil }
        return (start, end)
    }

    private static func seconds(_ clock: Substring) -> Double? {
        let parts = clock.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count), let seconds = Double(parts[parts.count - 1]),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    private static let markup = try! NSRegularExpression(pattern: #"<[^>]*>|\{\\[^}]*\}"#)
    private static let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
                                   "&lrm;": "", "&rlm;": ""]

    /// One line without its HTML-style tags (`<i>`, `<v Mia>`, `<00:01.000>`), its ASS style codes (`{\an8}`) and
    /// character entities.
    private static func strip(_ line: String) -> String {
        var text = markup.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        for (entity, plain) in entities { text = text.replacingOccurrences(of: entity, with: plain) }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// What language a run of text is in, to catch subtitles in another language than the one chosen.
public enum SubtitleLanguage {
    /// The most likely language of `text` as a code that matches `LanguageProfile.whisperCode` (such as "es"), with
    /// how sure it is. nil when the text is too short or mixed to say.
    public static func guess(_ text: String) -> LanguageGuess? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4_000)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let top = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        let code = top.key.rawValue.split(separator: "-").first.map(String.init) ?? top.key.rawValue
        return LanguageGuess(code: code, confidence: top.value,
                             runnersUp: Dictionary(uniqueKeysWithValues: hypotheses.map { ($0.key.rawValue, $0.value) }))
    }
}

/// Which subtitle file goes with which video, from the files a person dropped together.
public enum SubtitlePairing {
    public struct Item: Equatable, Sendable {
        public let video: URL
        public let subtitles: URL?
        public init(video: URL, subtitles: URL?) { self.video = video; self.subtitles = subtitles }
    }

    public struct Result: Equatable, Sendable {
        public let items: [Item]
        /// Subtitle files with no video to go with.
        public let unmatched: [URL]
    }

    public static func isSubtitle(_ url: URL) -> Bool { SubtitleParser.fileExtensions.contains(url.pathExtension.lowercased()) }

    /// Pairs by name: `Film.mp4` with `Film.srt`, or with `Film.es.srt` (a language tag before the extension). If
    /// two subtitle files fit one video, the one tagged with `language` (a code such as "es") is used. A lone subtitle
    /// file dropped with a lone video belongs to it whatever its name.
    public static func pair(_ urls: [URL], language: String? = nil) -> Result {
        let subtitles = urls.filter(isSubtitle)
        let videos = urls.filter { !isSubtitle($0) }
        var taken = Set<URL>()
        var items: [Item] = []
        for video in videos {
            let name = stem(video)
            let fits = subtitles.filter { !taken.contains($0) && base(of: $0) == name }
            let chosen = fits.first { tag(of: $0) == language?.lowercased() } ?? fits.first
            if let chosen { taken.insert(chosen) }
            items.append(Item(video: video, subtitles: chosen))
        }
        let left = subtitles.filter { !taken.contains($0) }
        if videos.count == 1, left.count == 1, items[0].subtitles == nil {
            items[0] = Item(video: videos[0], subtitles: left[0])
            return Result(items: items, unmatched: [])
        }
        return Result(items: items, unmatched: left)
    }

    private static func stem(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }

    /// The file name without its extension and without a trailing language tag: "film.es" is "film".
    private static func base(of subtitle: URL) -> String {
        let name = stem(subtitle)
        guard let dot = name.lastIndex(of: "."), isLanguageTag(String(name[name.index(after: dot)...])) else { return name }
        return String(name[..<dot])
    }

    private static func tag(of subtitle: URL) -> String? {
        let name = stem(subtitle)
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let tag = String(name[name.index(after: dot)...])
        return isLanguageTag(tag) ? tag.split(separator: "-").first.map(String.init) : nil
    }

    /// "es", "eng", "pt-br": two or three letters, then optionally a region.
    private static func isLanguageTag(_ text: String) -> Bool {
        text.range(of: #"^[a-z]{2,3}([-_][a-z]{2,4})?$"#, options: .regularExpression) != nil
    }
}
