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
    /// In a lesson's quiz a missed word is asked again until it is right, as the quiz is how the lesson sinks in.
    private let repeatsMisses: Bool
    /// A lesson's words, started only once the whole quiz has been answered: a lesson stopped half way started nothing.
    private var startsOnCompletion: [Int64]
    public private(set) var answered = 0
    public private(set) var correctFirstTry = 0
    /// In a known-words check: how many were missed, and so went back to being learned.
    public private(set) var returnedToLearning = 0

    /// What the latest answer changed, so that it can be taken back. Only a real review keeps one (the other kinds change
    /// no stage), and only the latest answer can be undone.
    private struct Undoable {
        var wordID: Int64
        var correct: Bool
        var at: Date
        var change: WordChange?          // nil when the answer wrote nothing (a missed word asked again)
        var wasFirstAnswer: Bool         // counted towards `correctFirstTry`
        var addedToMissed: Bool
        var requeued: Bool
    }
    private var latest: Undoable?
    public var canUndo: Bool { latest != nil }

    public init(database: LangDatabase, language: String, preferring: (@Sendable (ExampleLine) -> Bool)? = nil, now: Date = Date()) async throws {
        self.database = database
        self.language = language
        self.preferring = preferring
        isKnownCheck = false
        isPractice = false
        repeatsMisses = false
        startsOnCompletion = []
        queue = try await database.dueWords(language: language, now: now).compactMap(\.id)
    }

    /// A quick check of a few words you marked known. A missed word goes back to being learned (so a video's coverage
    /// stops counting it as known); a word you knew is left alone.
    public init(checkingKnown database: LangDatabase, language: String, count: Int = 10,
                preferring: (@Sendable (ExampleLine) -> Bool)? = nil) async throws {
        self.database = database
        self.language = language
        self.preferring = preferring
        isKnownCheck = true
        isPractice = false
        repeatsMisses = false
        startsOnCompletion = []
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
        repeatsMisses = false
        startsOnCompletion = []
        queue = try await database.practiceSample(kind, language: language, count: count, now: now)
    }

    /// The quiz at the end of a lesson: these words, asked now, with a missed word asked again until it is right. The
    /// answers change nothing; when the last one is right the words are started, their first review a stage-1 interval
    /// away. Stopping before that starts none of them, so a lesson is only done when both parts are.
    public init(lessonQuiz wordIDs: [Int64], database: LangDatabase, language: String,
                preferring: (@Sendable (ExampleLine) -> Bool)? = nil) {
        self.database = database
        self.language = language
        self.preferring = preferring
        isKnownCheck = false
        isPractice = true
        repeatsMisses = true
        startsOnCompletion = wordIDs
        queue = wordIDs
    }

    public var remaining: Int { queue.count }

    /// The card for the front of the queue. Stable until it is answered, so the sentence shown is the one played.
    public func currentCard() async throws -> ReviewCard? {
        if let cached, cached.id == queue.first { return cached }
        guard let id = queue.first else { return nil }
        let word = try await database.writer.read { try Word.fetchOne($0, key: id) }
        guard let word else { queue.removeFirst(); return try await currentCard() }
        let examples = try await database.examples(wordID: id, limit: 50)
        // How the word is spelt in your videos picks which capitalisation's entry leads (dorado, not the constellation Dorado).
        let entries = try await database.lookup(language: language, term: word.lemma, limit: 3,
                                                surface: DictionaryStore.commonSurface(of: examples.map(\.surface)))
        let liked = preferring.map { examples.filter($0) } ?? []
        let example = ExamplePicker.pick(from: liked.isEmpty ? examples : liked, avoiding: lastExample[id])
        lastExample[id] = example?.id
        let card = ReviewCard(word: word, entries: entries, example: example)
        cached = card
        return card
    }

    /// Drops the card at the front without answering it, for a card that can no longer be asked (its sentence was edited
    /// and no longer has the word). Nothing about the word changes, so in a review it is simply asked next time; in a
    /// lesson's quiz it is left out of the words that get started. Returns false if there was no card.
    @discardableResult
    public func skipCurrent(now: Date = Date()) async throws -> Bool {
        guard let id = queue.first else { return false }
        queue.removeAll { $0 == id }
        cached = nil
        let wasLessonWord = startsOnCompletion.contains(id)
        startsOnCompletion.removeAll { $0 == id }
        if wasLessonWord, queue.isEmpty, !startsOnCompletion.isEmpty {
            try await database.startLearning(wordIDs: startsOnCompletion, now: now, firstReviewAfter: SRS.intervals[0])
        }
        return true
    }

    public func answer(correct: Bool, now: Date = Date()) async throws {
        guard let id = queue.first else { return }
        queue.removeFirst()
        cached = nil
        latest = nil
        if isPractice {
            answered += 1
            if correct {
                if !missed.contains(id) { correctFirstTry += 1 }
            } else if repeatsMisses {
                missed.insert(id)
                queue.append(id)
            }
            if queue.isEmpty, !startsOnCompletion.isEmpty {
                try await database.startLearning(wordIDs: startsOnCompletion, now: now, firstReviewAfter: SRS.intervals[0])
            }
            return
        }
        if isKnownCheck {
            answered += 1
            if correct { correctFirstTry += 1 }
            else {
                try await database.startLearning(wordID: id, now: now)
                returnedToLearning += 1
            }
            return
        }
        let firstAnswer = !missed.contains(id)
        var change: WordChange?
        if firstAnswer {
            let before = try await database.snapshot(of: [id])
            do {
                let after = try await database.recordReview(wordID: id, correct: correct, now: now)
                change = WordChange(before: before, after: [after])
            } catch LangError.notLearning {
                // The word left learning during the session (marked known or ignored). Drop the card: it is not
                // asked again and counts as neither right nor missed.
                return
            }
            if correct { correctFirstTry += 1 }
        }
        answered += 1
        let addsToMissed = !correct && !missed.contains(id)
        if !correct {
            missed.insert(id)
            queue.append(id)
        }
        latest = Undoable(wordID: id, correct: correct, at: now, change: change, wasFirstAnswer: firstAnswer,
                          addedToMissed: addsToMissed, requeued: !correct)
    }

    /// Takes back the latest answer: the word's stage, next review and tally go back, and the card is the next one asked
    /// again. Returns false, and changes nothing, if there is no answer to take back or the word has moved on since.
    @discardableResult
    public func undoLast() async throws -> Bool {
        guard let last = latest else { return false }
        latest = nil
        if let change = last.change {
            guard try await database.undoReview(change, correct: last.correct, answeredAt: last.at) else { return false }
        }
        if last.requeued, queue.last == last.wordID { queue.removeLast() }
        if last.addedToMissed { missed.remove(last.wordID) }
        if last.correct, last.wasFirstAnswer { correctFirstTry -= 1 }
        answered -= 1
        queue.insert(last.wordID, at: 0)
        cached = nil
        return true
    }
}
