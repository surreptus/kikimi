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
    /// The exam level KANJIDIC2 gives, on the exam's older four levels (4 easiest). nil for a kanji no level asked for.
    public let jlpt: Int?
    /// The school grade: 1 to 6 for the elementary years, 8 for secondary school, 9 and 10 for kanji used in names.
    public let grade: Int?
    public var id: String { literal }

    public init(literal: String, onReadings: [String], kunReadings: [String], meanings: [String], jlpt: Int? = nil, grade: Int? = nil) {
        self.literal = literal; self.onReadings = onReadings; self.kunReadings = kunReadings; self.meanings = meanings
        self.jlpt = jlpt; self.grade = grade
    }

    /// The level as today's exam names it. The older four levels line up with them (103 kanji at the easiest level and
    /// N5's roughly 100, 181 and N4's, and so on), except that the older level 2 holds both N3's and N2's kanji.
    public var jlptLevels: String? {
        switch jlpt {
        case 4: "N5"
        case 3: "N4"
        case 2: "N3–N2"
        case 1: "N1"
        default: nil
        }
    }

    public enum Grade: Equatable, Sendable {
        case year(Int)
        /// Taught after elementary school, among the everyday kanji.
        case secondary
        /// Allowed in people's names.
        case names
    }

    public var schoolGrade: Grade? {
        switch grade {
        case .some(let year) where (1...6).contains(year): .year(year)
        case 8: .secondary
        case 9, 10: .names
        default: nil
        }
    }
}

/// The kanji data, read in place from the built file bundled in the app, like the dictionaries.
public final class KanjiStore: Sendable {
    public static let empty = KanjiStore()

    private let files: [String: ReopeningReader]
    /// Languages whose file has the level and grade columns; a file built before them still opens, without.
    private let withLevels: Set<String>

    private init() { files = [:]; withLevels = [] }

    /// `files` maps a language code to its built kanji file.
    public init(files: [String: URL]) throws {
        let opened = try files.mapValues { try ReopeningReader(url: $0) }
        self.files = opened
        withLevels = Set(try opened.compactMap { language, reader in
            try reader.readNow { try $0.columns(in: "kanji").contains { $0.name == "jlpt" } } ? language : nil
        })
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
        let levels = withLevels.contains(language) ? "jlpt, grade" : "NULL AS jlpt, NULL AS grade"
        let found: [String: KanjiInfo] = try await file.read { db in
            let marks = databaseQuestionMarks(count: characters.count)
            let rows = try Row.fetchAll(db, sql: "SELECT literal, on_yomi, kun_yomi, meaning, \(levels) FROM kanji WHERE literal IN (\(marks))",
                                        arguments: StatementArguments(characters))
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let literal: String = row["literal"]
                return (literal, KanjiInfo(
                    literal: literal,
                    onReadings: Self.split(row["on_yomi"], by: "、"),
                    kunReadings: Self.split(row["kun_yomi"], by: "、"),
                    meanings: Self.split(row["meaning"], by: "; "), jlpt: row["jlpt"], grade: row["grade"]))
            })
        }
        return characters.compactMap { found[$0] }
    }

    private static func split(_ text: String, by separator: String) -> [String] {
        text.components(separatedBy: separator).filter { !$0.isEmpty }
    }
}
