import Foundation
import GRDB

public enum LangError: Error, DetailedError, Equatable {
    case notFound
    case notLearning
    case emptyTitle
    case emptyLine
    /// A line must start at or after 0, end after it starts, and stay within the video.
    case badTiming

    public var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "Kikimi can't find that any more. Close this window and open it again.", bundle: .module)
        case .notLearning: String(localized: "This isn't one of the languages you are learning, so Kikimi can't do that.", bundle: .module)
        case .emptyTitle: String(localized: "A title can't be empty.", bundle: .module)
        case .emptyLine: String(localized: "A line can't be empty. Type some text, or cancel.", bundle: .module)
        case .badTiming: String(localized: "The start must come before the end, and both must be inside the video. Change the times and try again.", bundle: .module)
        }
    }

    public var detail: String { "LangError.\(self)" }
}

public final class LangDatabase: Sendable {
    public let writer: any DatabaseWriter
    /// Dictionary lookups; read directly from the built dictionary files, never copied into this database.
    public let dictionaries: DictionaryStore

    public init(path: String, dictionaries: DictionaryStore = .empty) throws {
        writer = try DatabasePool(path: path)
        self.dictionaries = dictionaries
        try LangMigrations.migrator().migrate(writer)
        try Self.reclaimFreeSpace(writer)
    }

    /// In-memory database for tests.
    public init(dictionaries: DictionaryStore = .empty) throws {
        writer = try DatabaseQueue()
        self.dictionaries = dictionaries
        try LangMigrations.migrator().migrate(writer)
    }

    /// Dropping the old dictionary copy leaves the file full of free pages; give them back once.
    private static func reclaimFreeSpace(_ writer: any DatabaseWriter) throws {
        try writer.writeWithoutTransaction { db in
            let free = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
            if free > 2_000 { try db.execute(sql: "VACUUM") }   // over about 8 MB of free pages
        }
    }

    // MARK: Words

    /// Puts a word into the review queue at stage 1, due immediately.
    /// A word that is already learning or finished stays as it is, like the bulk version.
    public func startLearning(wordID: Int64, now: Date = Date()) async throws {
        try await writer.write { db in
            guard var word = try Word.fetchOne(db, key: wordID) else { throw LangError.notFound }
            guard word.status != .learning && word.status != .finished else { return }
            word.status = .learning
            word.stage = .stage1
            word.nextReview = now
            try word.update(db)
            try Self.bump(.learn, subject: wordID, at: now, in: db)
        }
    }

    public func markKnown(wordID: Int64) async throws {
        try await writer.write { db in
            guard var word = try Word.fetchOne(db, key: wordID) else { throw LangError.notFound }
            let changed = word.status != .known
            word.status = .known
            word.stage = nil
            word.nextReview = nil
            try word.update(db)
            if changed { try Self.bump(.known, subject: wordID, at: Date(), in: db) }
        }
    }

    /// Applies an SRS answer to a word that is being learned. The next review is moved a little by `jitter`
    /// (see `SRS.variation`); the default is random, and tests pass a fixed number.
    @discardableResult
    public func recordReview(wordID: Int64, correct: Bool, now: Date = Date(),
                             jitter: Double = SRS.randomJitter()) async throws -> Word {
        try await writer.write { db in
            guard var word = try Word.fetchOne(db, key: wordID) else { throw LangError.notFound }
            guard word.status == .learning, let stage = word.stage else { throw LangError.notLearning }
            let result = SRS.answer(stage: stage, correct: correct, now: now, jitter: jitter)
            word.stage = result.stage
            word.nextReview = result.nextReview
            word.status = result.stage == .finished ? .finished : .learning
            try word.update(db)
            try Self.bump(.review, subject: wordID, at: now, in: db)
            if correct { try Self.bump(.reviewCorrect, subject: wordID, at: now, in: db) }
            return word
        }
    }

    /// The words due now, the longest overdue first. `limit` keeps a session short: the rest stay due for the next one.
    public func dueWords(language: String, now: Date = Date(), limit: Int? = nil) async throws -> [Word] {
        try await writer.read { db in
            let request = Word
                .filter(Column("language") == language && Column("status") == WordStatus.learning.rawValue
                        && Column("next_review") <= now)
                .order(Column("next_review"), Column("id"))
            return try (limit.map { request.limit($0) } ?? request).fetchAll(db)
        }
    }

    @discardableResult
    func updateWord(_ id: Int64, _ change: @Sendable @escaping (inout Word) throws -> Void) async throws -> Word {
        try await writer.write { db in
            guard var word = try Word.fetchOne(db, key: id) else { throw LangError.notFound }
            try change(&word)
            try word.update(db)
            return word
        }
    }
}
