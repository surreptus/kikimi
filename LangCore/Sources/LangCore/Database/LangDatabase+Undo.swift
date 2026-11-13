import Foundation
import GRDB

/// A change to some words that can be taken back: the words before it and after it.
public struct WordChange: Sendable {
    public let before: [Word]
    public let after: [Word]

    /// A change that moved nothing, such as Learn on a word already being learned. There is nothing to undo.
    public var isEmpty: Bool {
        before.count == after.count && zip(before, after).allSatisfy { LangDatabase.sameProgress($0, $1) }
    }
}

extension LangDatabase {
    /// Runs `body`, which changes these words, and returns the words as they were and as they are now.
    public func change(_ wordIDs: [Int64], _ body: @Sendable () async throws -> Void) async throws -> WordChange {
        let before = try await snapshot(of: wordIDs)
        try await body()
        return WordChange(before: before, after: try await snapshot(of: wordIDs))
    }

    /// Sets one word's status as the player's L, K and X keys do (`.known` and `.finished` both mean known).
    public func setStatus(_ status: WordStatus, ofWord id: Int64) async throws -> WordChange {
        try await change([id]) {
            switch status {
            case .learning: try await self.startLearning(wordID: id)
            case .ignored: try await self.markIgnored(wordIDs: [id])
            case .new: try await self.markNew(wordIDs: [id])
            default: try await self.markKnown(wordID: id)
            }
        }
    }

    /// Takes a change back. A word is put back only if it is still as the change left it: if you have moved it since (in
    /// another window, or by a later answer), your newer progress stays. Returns how many words were put back.
    @discardableResult
    public func undo(_ change: WordChange, now: Date = Date()) async throws -> Int {
        try await writer.write { db in try Self.restore(change.before, onlyIfStill: change.after, in: db, now: now) }
    }

    /// Takes back one review answer: the word's stage and next review, and the answer's tally (`review`, and
    /// `reviewCorrect` for a right one) on the day it was given. Does nothing, and returns false, if the word has
    /// moved on since the answer.
    func undoReview(_ change: WordChange, correct: Bool, answeredAt: Date) async throws -> Bool {
        try await writer.write { db in
            guard try Self.restore(change.before, onlyIfStill: change.after, in: db, now: answeredAt) > 0 else { return false }
            for word in change.before {
                guard let id = word.id else { continue }
                try Self.unbump(.review, subject: id, at: answeredAt, in: db)
                if correct { try Self.unbump(.reviewCorrect, subject: id, at: answeredAt, in: db) }
            }
            return true
        }
    }
}
