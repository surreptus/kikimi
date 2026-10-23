import Foundation
import GRDB

public enum LangError: Error, Equatable {
    case notFound
    case notLearning
    case emptyTitle
}

public final class LangDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(path: String) throws {
        writer = try DatabasePool(path: path)
        try LangMigrations.migrator().migrate(writer)
    }

    /// In-memory database for tests.
    public init() throws {
        writer = try DatabaseQueue()
        try LangMigrations.migrator().migrate(writer)
    }

    // MARK: Words

    /// Puts a word into the review queue at apprentice 1, due immediately.
    public func startLearning(wordID: Int64, now: Date = Date()) async throws {
        try await updateWord(wordID) { word in
            word.status = .learning
            word.stage = .apprentice1
            word.nextReview = now
        }
    }

    public func markKnown(wordID: Int64) async throws {
        try await updateWord(wordID) { word in
            word.status = .known
            word.stage = nil
            word.nextReview = nil
        }
    }

    /// Applies an SRS answer to a word that is being learned.
    @discardableResult
    public func recordReview(wordID: Int64, correct: Bool, now: Date = Date()) async throws -> Word {
        try await updateWord(wordID) { word in
            guard word.status == .learning, let stage = word.stage else { throw LangError.notLearning }
            let result = SRS.answer(stage: stage, correct: correct, now: now)
            word.stage = result.stage
            word.nextReview = result.nextReview
            word.status = result.stage == .burned ? .burned : .learning
        }
    }

    public func dueWords(language: String, now: Date = Date()) async throws -> [Word] {
        try await writer.read { db in
            try Word
                .filter(Column("language") == language && Column("status") == WordStatus.learning.rawValue
                        && Column("next_review") <= now)
                .order(Column("next_review"))
                .fetchAll(db)
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
