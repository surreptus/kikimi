import XCTest
@testable import LangCore

/// Opt-in: tokenizes real subtitle files with the real profile and prints what looks wrong (see `TokenAudit`).
///
/// - `KIKIMI_TOKEN_AUDIT=<folder or file>` runs it. A folder is searched for .srt and .vtt files. The files are only read.
/// - A file's language is the start of its name before the first "-" ("es-short.srt"), or `KIKIMI_AUDIT_LANG` for all files.
/// - `KIKIMI_AUDIT_TOP=<n>` sets how many suspects each section lists (25).
/// - `KIKIMI_AUDIT_SAVE=<file>` writes the report as JSON, to be a baseline later. It needs one language.
/// - `KIKIMI_AUDIT_BASELINE=<file>` also prints which suspects are new and which are gone since that file. One language.
final class TokenAuditRunTests: XCTestCase {
    func testAuditSubtitleFiles() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["KIKIMI_TOKEN_AUDIT"] else { throw XCTSkip("Set KIKIMI_TOKEN_AUDIT to a folder of subtitle files to run.") }
        let top = Int(env["KIKIMI_AUDIT_TOP"] ?? "") ?? 25

        var byLanguage: [String: [URL]] = [:]
        for file in try Self.subtitleFiles(at: input) {
            let code = env["KIKIMI_AUDIT_LANG"] ?? String(file.lastPathComponent.prefix { $0 != "-" })
            byLanguage[code, default: []].append(file)
        }
        XCTAssertFalse(byLanguage.isEmpty, "no .srt or .vtt files in \(input)")
        let oneFile = env["KIKIMI_AUDIT_SAVE"] != nil || env["KIKIMI_AUDIT_BASELINE"] != nil
        if oneFile, byLanguage.count > 1 {
            XCTFail("KIKIMI_AUDIT_SAVE and KIKIMI_AUDIT_BASELINE need one language. Set KIKIMI_AUDIT_LANG, or use a folder of one.")
            return
        }

        for (code, urls) in byLanguage.sorted(by: { $0.key < $1.key }) {
            guard let profile = LanguageProfiles.profile(for: code) else { print("\n\(code): no such language profile, skipped"); continue }
            let report = try await Self.audit(profile, files: urls)
            print("\n" + TokenAudit.render(report, top: top))
            if let path = env["KIKIMI_AUDIT_BASELINE"] {
                let baseline = try TokenAudit.decode(Data(contentsOf: URL(fileURLWithPath: path)))
                print("\n" + TokenAudit.render(TokenAudit.diff(report, against: baseline), top: top))
            }
            if let path = env["KIKIMI_AUDIT_SAVE"] {
                try TokenAudit.encode(report).write(to: URL(fileURLWithPath: path), options: .atomic)
                print("\nSaved the report to \(path)")
            }
        }
    }

    private static func subtitleFiles(at path: String) throws -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { throw XCTSkip("\(path) does not exist.") }
        guard isFolder.boolValue else { return [url] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter(SubtitlePairing.isSubtitle).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The same path the import takes: parse, clean, then the profile's own content words.
    private static func audit(_ profile: any LanguageProfile, files: [URL]) async throws -> AuditReport {
        var cues: [TranscriptSegment] = []
        for file in files {
            let parsed = try XCTUnwrap(SubtitleParser.parse(Data(contentsOf: file), lineJoiner: profile.dictationSeparator), file.lastPathComponent)
            cues += TranscriptCleaner.clean(parsed)
        }
        let store = try? DictionaryStore.bundled(for: [profile])
        if store == nil { print("\(profile.code): dictionary file missing; the dictionary checks are skipped.") }
        var known: [String: Bool] = [:]
        var tokens: [AuditToken] = []
        for cue in cues {
            let text = cue.text
            let content = Set(profile.contentWords(in: text).map { "\($0.surface)|\($0.lemma)|\($0.pos.rawValue)" })
            for token in profile.tokenizer.tokens(in: text) {
                let isContent = content.contains("\(token.surface)|\(token.lemma)|\(token.pos.rawValue)")
                var hasEntry: Bool?
                if isContent, let store {
                    if let seen = known[token.lemma] { hasEntry = seen } else {
                        let entries = try await store.lookup(language: profile.code, term: token.lemma, limit: 1, surface: token.surface)
                        known[token.lemma] = !entries.isEmpty
                        hasEntry = !entries.isEmpty
                    }
                }
                tokens.append(AuditToken(surface: token.surface, lemma: token.lemma, pos: token.pos, isCutOff: token.isCutOff,
                                         isContent: isContent, hasEntry: hasEntry, sentence: text))
            }
        }
        return TokenAudit.report(language: profile.code, lines: cues.count, tokens: tokens,
                                 infinitiveEndings: TokenAudit.infinitiveEndings[profile.code] ?? [])
    }
}
