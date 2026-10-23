import Foundation
import GRDB

public enum DictionaryError: Error {
    case missingResource(String)
}

extension LangDatabase {
    public func hasDictionary(language: String) async throws -> Bool {
        try await writer.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM dictionary WHERE language = ?)", arguments: [language]) ?? false
        }
    }

    /// Copies the profile's bundled dictionary into `dictionary` the first time it is needed.
    /// Returns whether anything was imported.
    @discardableResult
    public func importBundledDictionary(
        for profile: any LanguageProfile, bundle: Bundle? = nil
    ) async throws -> Bool {
        if try await hasDictionary(language: profile.code) { return false }
        let name = profile.dictionarySource.resourceName
        guard let url = (bundle ?? .module).url(forResource: name, withExtension: "sqlite", subdirectory: "dictionaries") else {
            throw DictionaryError.missingResource(name)
        }
        try await importDictionary(from: url, language: profile.code)
        return true
    }

    /// Replaces the language's dictionary rows with the `entries` table of a built dictionary file.
    public func importDictionary(from url: URL, language: String) async throws {
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS dict_src", arguments: [url.path])
            defer { try? db.execute(sql: "DETACH DATABASE dict_src") }
            try db.inTransaction {
                try db.execute(sql: "DELETE FROM dictionary WHERE language = ?", arguments: [language])
                try db.execute(sql: """
                    INSERT INTO dictionary (language, headword, reading, gloss)
                    SELECT ?, headword, reading, gloss FROM dict_src.entries ORDER BY id
                    """, arguments: [language])
                return .commit
            }
        }
    }

    /// Entries whose headword or reading equals `term`; headword matches first, then source order (common words first).
    public func lookup(language: String, term: String, limit: Int = 20) async throws -> [DictionaryEntry] {
        try await writer.read { db in
            try DictionaryEntry
                .filter(Column("language") == language && (Column("headword") == term || Column("reading") == term))
                .order(sql: "headword = ? DESC, id", arguments: [term])
                .limit(limit)
                .fetchAll(db)
        }
    }
}
