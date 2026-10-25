import Foundation

public struct ReviewCard: Sendable, Identifiable {
    public let word: Word
    public let entries: [DictionaryEntry]
    public let example: ExampleLine?
    public var id: Int64 { word.id! }
}

/// Chooses which example line a card shows (and plays).
public enum ExamplePicker {
    /// A random example, never the one just used unless it is the only choice.
    public static func pick<G: RandomNumberGenerator>(
        from examples: [ExampleLine], avoiding lastID: Int64? = nil, using generator: inout G
    ) -> ExampleLine? {
        let fresh = examples.filter { $0.id != lastID }
        return (fresh.isEmpty ? examples : fresh).randomElement(using: &generator)
    }

    public static func pick(from examples: [ExampleLine], avoiding lastID: Int64? = nil) -> ExampleLine? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: examples, avoiding: lastID, using: &generator)
    }
}

/// One sitting of reviews. A word's SRS stage changes once per session, on its first answer;
/// a missed word comes back later in the session but does not change stage again.
public actor ReviewSession {
    private let database: LangDatabase
    private let language: String
    private var queue: [Int64] = []
    private var missed: Set<Int64> = []
    private var lastExample: [Int64: Int64] = [:]   // word id -> subtitle id shown last
    private var cached: ReviewCard?
    public private(set) var answered = 0
    public private(set) var correctFirstTry = 0

    public init(database: LangDatabase, language: String, now: Date = Date()) async throws {
        self.database = database
        self.language = language
        queue = try await database.dueWords(language: language, now: now).compactMap(\.id)
    }

    public var remaining: Int { queue.count }

    /// The card for the front of the queue. Stable until it is answered, so the sentence shown is the one played.
    public func currentCard() async throws -> ReviewCard? {
        if let cached, cached.id == queue.first { return cached }
        guard let id = queue.first else { return nil }
        let word = try await database.writer.read { try Word.fetchOne($0, key: id) }
        guard let word else { queue.removeFirst(); return try await currentCard() }
        let entries = try await database.lookup(language: language, term: word.lemma, limit: 3)
        let examples = try await database.examples(wordID: id, limit: 50)
        let example = ExamplePicker.pick(from: examples, avoiding: lastExample[id])
        lastExample[id] = example?.id
        let card = ReviewCard(word: word, entries: entries, example: example)
        cached = card
        return card
    }

    public func answer(correct: Bool, now: Date = Date()) async throws {
        guard let id = queue.first else { return }
        queue.removeFirst()
        cached = nil
        answered += 1
        if !missed.contains(id) {
            try await database.recordReview(wordID: id, correct: correct, now: now)
            if correct { correctFirstTry += 1 }
        }
        if !correct {
            missed.insert(id)
            queue.append(id)
        }
    }
}
