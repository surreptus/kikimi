import Foundation
import GRDB

/// One kanji with how it is read and what it means.
public struct KanjiInfo: Sendable, Equatable, Identifiable {
    public let literal: String
    /// Readings borrowed from Chinese (音読み), in katakana: ゲツ, ガツ.
    public let onReadings: [String]
    /// Native readings (訓読み), in hiragana, with a "." where the okurigana begins: た.べる.
    public let kunReadings: [String]
    public let meanings: [String]
    public var id: String { literal }

    public init(literal: String, onReadings: [String], kunReadings: [String], meanings: [String]) {
        self.literal = literal; self.onReadings = onReadings; self.kunReadings = kunReadings; self.meanings = meanings
    }
}

/// The kanji data, read in place from the built file bundled in the app, like the dictionaries.
public final class KanjiStore: Sendable {
    public static let empty = KanjiStore()

    private let files: [String: DatabaseQueue]

    private init() { files = [:] }

    /// `files` maps a language code to its built kanji file.
    public init(files: [String: URL]) throws {
        var configuration = Configuration()
        configuration.readonly = true
        self.files = try files.mapValues { try DatabaseQueue(path: $0.path, configuration: configuration) }
    }

    /// Opens the kanji file each profile that has one names, from the app bundle.
    public static func bundled(for profiles: [any LanguageProfile], bundle: Bundle? = nil) throws -> KanjiStore {
        var urls: [String: URL] = [:]
        for profile in profiles {
            guard let name = profile.kanjiResourceName else { continue }
            guard let url = (bundle ?? .module).url(forResource: name, withExtension: "sqlite", subdirectory: "dictionaries") else {
                throw DictionaryError.missingResource(name)
            }
            urls[profile.code] = url
        }
        return try KanjiStore(files: urls)
    }

    /// The kanji in `word`, each once, in the order they first appear. Characters that are not in the data (kana,
    /// letters, rare kanji) are skipped.
    public func kanji(in word: String, language: String) async throws -> [KanjiInfo] {
        guard let file = files[language] else { return [] }
        var seen = Set<Character>()
        let characters = word.filter { seen.insert($0).inserted }.map(String.init)
        guard !characters.isEmpty else { return [] }
        let found: [String: KanjiInfo] = try await file.read { db in
            let marks = databaseQuestionMarks(count: characters.count)
            let rows = try Row.fetchAll(db, sql: "SELECT literal, on_yomi, kun_yomi, meaning FROM kanji WHERE literal IN (\(marks))",
                                        arguments: StatementArguments(characters))
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let literal: String = row["literal"]
                return (literal, KanjiInfo(
                    literal: literal,
                    onReadings: Self.split(row["on_yomi"], by: "、"),
                    kunReadings: Self.split(row["kun_yomi"], by: "、"),
                    meanings: Self.split(row["meaning"], by: "; ")))
            })
        }
        return characters.compactMap { found[$0] }
    }

    private static func split(_ text: String, by separator: String) -> [String] {
        text.components(separatedBy: separator).filter { !$0.isEmpty }
    }
}
