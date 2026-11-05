import Foundation

public struct ReviewCard: Sendable, Identifiable {
    public let word: Word
    public let entries: [DictionaryEntry]
    public let example: ExampleLine?
    public var id: Int64 { word.id! }

    public init(word: Word, entries: [DictionaryEntry], example: ExampleLine?) {
        self.word = word; self.entries = entries; self.example = example
    }

    /// The same card showing a different example (a line whose text was corrected).
    public func showing(_ example: ExampleLine?) -> ReviewCard {
        ReviewCard(word: word, entries: entries, example: example)
    }
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
    /// Lines to choose among when the card's kind needs a certain sort of line (a short one to type); any line when
    /// the word has none that qualify.
    private let preferring: (@Sendable (ExampleLine) -> Bool)?
    /// A check of words marked known, not a review: answers don't move any stage.
    public let isKnownCheck: Bool
    /// Extra study (review ahead, practice finished): answers are counted and nothing else changes.
    public let isPractice: Bool
    public private(set) var answered = 0
    public private(set) var correctFirstTry = 0
    /// In a known-words check: how many were missed, and so went back to being learned.
    public private(set) var returnedToLearning = 0

    public init(database: LangDatabase, language: String, preferring: (@Sendable (ExampleLine) -> Bool)? = nil, now: Date = Date()) async throws {
        self.database = database
        self.language = language
        self.preferring = preferring
        isKnownCheck = false
        isPractice = false
        queue = try await database.dueWords(language: language, now: now).compactMap(\.id)
    }

    /// A quick check of a few words you marked known. A missed word goes back to being learned (so a video's coverage
    /// stops counting it as known); a word you knew is left alone.
    public init(checkingKnown database: LangDatabase, language: String, count: Int = 10) async throws {
        self.database = database
        self.language = language
        preferring = nil
        isKnownCheck = true
        isPractice = false
        queue = try await database.knownSample(language: language, count: count)
    }

    /// Extra study that changes no stage and no status, so it can be done any time without disturbing the schedule.
    public init(practising kind: PracticeKind, database: LangDatabase, language: String,
                preferring: (@Sendable (ExampleLine) -> Bool)? = nil, count: Int = 20, now: Date = Date()) async throws {
        self.database = database
        self.language = language
        self.preferring = preferring
        isKnownCheck = false
        isPractice = true
        queue = try await database.practiceSample(kind, language: language, count: count, now: now)
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
        let liked = preferring.map { examples.filter($0) } ?? []
        let example = ExamplePicker.pick(from: liked.isEmpty ? examples : liked, avoiding: lastExample[id])
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
        if isPractice {
            if correct { correctFirstTry += 1 }
            return
        }
        if isKnownCheck {
            if correct { correctFirstTry += 1 }
            else {
                try await database.startLearning(wordID: id, now: now)
                returnedToLearning += 1
            }
            return
        }
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
