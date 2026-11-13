import XCTest
@testable import LangCore

/// Opt-in check: tokenizes subtitle files and writes surface, lemma, part of speech and "content" to a TSV file, so two runs
/// (before and after a tokenizer change) can be compared. Set `KIKIMI_SRT_FILES` (colon-separated paths) and `KIKIMI_TOKEN_DUMP`.
final class SpanishClipDumpTests: XCTestCase {
    func testDumpTokens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let files = env["KIKIMI_SRT_FILES"], let out = env["KIKIMI_TOKEN_DUMP"] else {
            throw XCTSkip("Set KIKIMI_SRT_FILES and KIKIMI_TOKEN_DUMP to run.")
        }
        let profile = SpanishProfile()
        var rows: [String] = []
        for path in files.split(separator: ":") {
            let text = try String(contentsOfFile: String(path), encoding: .utf8)
            for cue in SubtitleParser.parse(text) {
                let trimmed = cue.text
                let content = Set(profile.contentWords(in: trimmed).map { "\($0.surface)|\($0.lemma)|\($0.pos.rawValue)" })
                for token in profile.tokenizer.tokens(in: trimmed) {
                    let key = "\(token.surface)|\(token.lemma)|\(token.pos.rawValue)"
                    rows.append("\(token.surface)\t\(token.lemma)\t\(token.pos.rawValue)\t\(content.contains(key) ? "content" : "-")\t\(trimmed)")
                }
            }
        }
        try rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
