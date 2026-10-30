import Foundation
import Translation

/// Whether lines can be translated between two languages right now.
public enum TranslationAvailability: Equatable, Sendable {
    case ready
    /// macOS supports the pair but its language data isn't on this Mac yet.
    case needsDownload
    case unavailable
}

/// Turns subtitle lines into another language. The app uses macOS's own translation; tests use a stand-in.
public protocol LineTranslator: Sendable {
    func availability() async -> TranslationAvailability
    /// The translation of each line, in the same order; nil for a line that has nothing to translate or that failed.
    func translate(_ lines: [String]) async throws -> [String?]
}

/// Translates on this Mac with the system's Translation framework. Nothing is sent anywhere; macOS may download a
/// language's data once, from the system's own settings.
public actor AppleLineTranslator: LineTranslator {
    private let source: Locale.Language
    private let target: Locale.Language
    private var session: TranslationSession?

    public init(source: String, target: String) {
        self.source = Locale.Language(identifier: source)
        self.target = Locale.Language(identifier: target)
    }

    public func availability() async -> TranslationAvailability {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .ready
        case .supported: .needsDownload
        default: .unavailable
        }
    }

    public func translate(_ lines: [String]) async throws -> [String?] {
        let session = self.session ?? TranslationSession(installedSource: source, target: target)
        self.session = session
        var result = [String?](repeating: nil, count: lines.count)
        // A line with no letters in it (a lone "♪", "...") has nothing to translate and makes the framework refuse it.
        let wanted = lines.indices.filter { TranslationText.hasWords(lines[$0]) }
        guard !wanted.isEmpty else { return result }
        do {
            let requests = wanted.map { TranslationSession.Request(sourceText: lines[$0], clientIdentifier: "\($0)") }
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier, let index = Int(id), result.indices.contains(index) {
                    result[index] = response.targetText
                }
            }
        } catch {
            // One refused line shouldn't cost the whole batch: go line by line.
            for index in wanted {
                result[index] = try? await session.translate(lines[index]).targetText
            }
        }
        return result
    }
}

enum TranslationText {
    /// Whether the text has a letter or digit in any script, so there is something to translate.
    static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
