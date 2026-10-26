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

    public init(id: Int64? = nil, language: String, headword: String, reading: String? = nil, gloss: String) {
        self.id = id; self.language = language; self.headword = headword
        self.reading = reading; self.gloss = gloss
    }
}

/// The dictionaries, read straight from the built files (the ones bundled in the app) without copying them into
/// the database: nothing is stored twice, and there is no import step. Each file is opened read-only.
public final class DictionaryStore: Sendable {
    public static let empty = DictionaryStore()

    private let files: [String: DatabaseQueue]

    private init() { files = [:] }

    /// `files` maps a language code to its built dictionary file.
    public init(files: [String: URL]) throws {
        var configuration = Configuration()
        configuration.readonly = true
        self.files = try files.mapValues { try DatabaseQueue(path: $0.path, configuration: configuration) }
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

    /// Entries whose headword or reading equals `term`; headword matches first, then file order (the commoner word first).
    /// A word's other capitalisations count too: the lemma is lower case, but a dictionary can keep a sense under the
    /// capitalised form (Wiktionary has "nochebuena" as the plant and "Nochebuena" as Christmas Eve).
    public func lookup(language: String, term: String, limit: Int) async throws -> [DictionaryEntry] {
        guard let file = files[language] else { return [] }
        let capitalised = term.prefix(1).uppercased() + term.dropFirst()
        return try await file.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, headword, reading, gloss FROM entries
                WHERE headword IN (?1, ?2, ?3, ?4) OR reading = ?1
                ORDER BY headword IN (?1, ?2, ?3, ?4) DESC, id
                LIMIT ?5
                """, arguments: [term, capitalised, term.lowercased(), term.uppercased(), limit]).map {
                DictionaryEntry(id: $0["id"], language: language, headword: $0["headword"],
                                reading: $0["reading"], gloss: $0["gloss"])
            }
        }
    }
}

extension LangDatabase {
    public func lookup(language: String, term: String, limit: Int = 20) async throws -> [DictionaryEntry] {
        try await dictionaries.lookup(language: language, term: term, limit: limit)
    }
}
