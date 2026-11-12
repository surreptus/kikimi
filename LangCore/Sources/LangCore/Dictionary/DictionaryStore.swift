import Foundation
import GRDB

public enum DictionaryError: Error {
    case missingResource(String)
}

/// One entry of a built dictionary file.
public struct DictionaryEntry: Sendable, Equatable, Identifiable {
    /// Row id within its dictionary file.
    public var id: Int64?
    public var language: String
    public var headword: String
    public var reading: String?
    public var gloss: String
    /// A noun's gender as letters, "m", "f" or "n", or a mix such as "m,f" for a word with two. nil for other words and
    /// for languages without it.
    public var gender: String?

    /// Whether the first meaning listed is a noun, so that a gender belongs to the word as it is first read. Dictionary
    /// text numbers each sense and labels its part of speech: "1. (noun) house".
    public var startsAsNoun: Bool { gloss.hasPrefix("1. (noun") }

    public init(id: Int64? = nil, language: String, headword: String, reading: String? = nil, gloss: String, gender: String? = nil) {
        self.id = id; self.language = language; self.headword = headword
        self.reading = reading; self.gloss = gloss; self.gender = gender
    }
}

/// The dictionaries, read straight from the built files (the ones bundled in the app) without copying them into
/// the database: nothing is stored twice, and there is no import step. Each file is opened read-only.
public final class DictionaryStore: Sendable {
    public static let empty = DictionaryStore()

    private let files: [String: ReopeningReader]
    /// Languages whose file has the gender column; a file built before it existed still opens, with no genders.
    private let withGender: Set<String>

    private init() { files = [:]; withGender = [] }

    /// `files` maps a language code to its built dictionary file.
    public init(files: [String: URL]) throws {
        let opened = try files.mapValues { try ReopeningReader(url: $0) }
        self.files = opened
        withGender = Set(try opened.compactMap { language, reader in
            try reader.readNow { try $0.columns(in: "entries").contains { $0.name == "gender" } } ? language : nil
        })
    }

    /// Opens the dictionary each profile names, from the app bundle.
    public static func bundled(for profiles: [any LanguageProfile], bundle: Bundle? = nil) throws -> DictionaryStore {
        var urls: [String: URL] = [:]
        for profile in profiles {
            let name = profile.dictionarySource.resourceName
            guard let url = (bundle ?? .module).url(forResource: name, withExtension: "sqlite", subdirectory: "dictionaries") else {
                throw DictionaryError.missingResource(name)
            }
            urls[profile.code] = url
        }
        return try DictionaryStore(files: urls)
    }

    public var languages: [String] { files.keys.sorted() }

    public func entryCount(language: String) async throws -> Int {
        guard let file = files[language] else { return 0 }
        return try await file.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries") ?? 0 }
    }

    /// Entries whose headword or reading equals `term`: headword matches first, then reading matches, each in file order (the
    /// commoner word first). A word's other capitalisations count too: the lemma is lower case, but a dictionary can keep a
    /// sense under the capitalised form (Wiktionary has "nochebuena" as the plant and "Nochebuena" as Christmas Eve).
    ///
    /// Which capitalisation comes first depends on how the word is spelt where it was met, since the lemma doesn't say:
    /// `surface` is that spelling. Capitalised in the video ("Navidad"), the capitalised entry leads; lower case ("dorado",
    /// golden, not the constellation "Dorado"), the lower-case one does. An all-capitals form (an abbreviation such as NO,
    /// "northwest") comes last unless it is what was met. With no `surface`, the entry for `term` as written leads.
    public func lookup(language: String, term: String, limit: Int, surface: String? = nil) async throws -> [DictionaryEntry] {
        guard let file = files[language] else { return [] }
        let capitalised = term.prefix(1).uppercased() + term.dropFirst()
        let lower = term.lowercased(), upper = term.uppercased()
        let order: [String]
        switch Self.capitalisation(of: surface) {
        case nil: order = [term, lower, capitalised, upper]
        case .lower?: order = [lower, term, capitalised, upper]
        case .capitalised?: order = [capitalised, lower, term, upper]
        case .upper?: order = [upper, capitalised, lower, term]
        }
        let gender = withGender.contains(language) ? "gender" : "NULL AS gender"
        return try await file.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, headword, reading, gloss, \(gender) FROM entries
                WHERE headword IN (?1, ?2, ?3, ?4) OR reading = ?1
                ORDER BY CASE headword WHEN ?5 THEN 0 WHEN ?6 THEN 1 WHEN ?7 THEN 2 WHEN ?8 THEN 3 ELSE 4 END, id
                LIMIT ?9
                """, arguments: StatementArguments([term, capitalised, lower, upper] + order) + [limit]).map {
                DictionaryEntry(id: $0["id"], language: language, headword: $0["headword"],
                                reading: $0["reading"], gloss: $0["gloss"], gender: $0["gender"])
            }
        }
    }

    /// Where a bundled dictionary file is, for tests that read it directly.
    static func bundledURL(_ resource: String) -> URL? {
        Bundle.module.url(forResource: resource, withExtension: "sqlite", subdirectory: "dictionaries")
    }

    enum Capitalisation { case lower, capitalised, upper }

    static func capitalisation(of surface: String?) -> Capitalisation? {
        guard let surface, let first = surface.first else { return nil }
        if surface.count > 1, surface == surface.uppercased(), surface != surface.lowercased() { return .upper }
        return first.isUppercase ? .capitalised : .lower
    }

    /// One spelling to stand for how a word is written across the lines it was met in: a capitalised one when most of them
    /// are capitalised, else a lower-case one. nil when there are none.
    public static func commonSurface(of surfaces: [String]) -> String? {
        let all = surfaces.filter { !$0.isEmpty }
        guard !all.isEmpty else { return nil }
        let capitalised = all.filter { $0.first?.isUppercase == true }
        if capitalised.count * 2 > all.count { return capitalised[0] }
        return all.first { $0.first?.isUppercase != true } ?? all[0]
    }
}

extension LangDatabase {
    public func lookup(language: String, term: String, limit: Int = 20, surface: String? = nil) async throws -> [DictionaryEntry] {
        try await dictionaries.lookup(language: language, term: term, limit: limit, surface: surface)
    }
}
