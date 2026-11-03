import Foundation
import GRDB
@testable import LangCore

/// Small dictionary files in the built format (an `entries` table with its indexes), opened the way the app opens
/// the real ones: read-only, in place.
enum TestDictionaries {
    typealias Entry = (headword: String, reading: String?, gloss: String)

    /// `genders` maps a headword to its gender letters; giving any makes the file the newer kind, with the column.
    static func makeFile(_ entries: [Entry], genders: [String: String] = [:], in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let url = directory.appending(path: "dict-\(UUID().uuidString).sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            let column = genders.isEmpty ? "" : ", gender TEXT"
            try db.execute(sql: "CREATE TABLE entries (id INTEGER PRIMARY KEY, headword TEXT NOT NULL, reading TEXT, gloss TEXT NOT NULL\(column))")
            for e in entries {
                if genders.isEmpty {
                    try db.execute(sql: "INSERT INTO entries (headword, reading, gloss) VALUES (?, ?, ?)", arguments: [e.headword, e.reading, e.gloss])
                } else {
                    try db.execute(sql: "INSERT INTO entries (headword, reading, gloss, gender) VALUES (?, ?, ?, ?)", arguments: [e.headword, e.reading, e.gloss, genders[e.headword]])
                }
            }
            try db.execute(sql: "CREATE INDEX entries_headword ON entries(headword)")
            try db.execute(sql: "CREATE INDEX entries_reading ON entries(reading)")
        }
        return url
    }

    static func store(_ languages: [String: [Entry]], genders: [String: String] = [:]) throws -> DictionaryStore {
        try DictionaryStore(files: languages.mapValues { try makeFile($0, genders: genders) })
    }
}
