import Foundation
import GRDB

/// Records map to snake_case columns.
public protocol LangRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {}

extension LangRecord {
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
}

public enum WordStatus: String, Codable, Sendable {
    case new, learning, known, burned
}

public struct Video: LangRecord {
    public static let databaseTableName = "videos"
    public var id: Int64?
    public var language: String
    public var title: String
    public var contentHash: String
    public var videoPath: String
    public var audioPath: String?
    public var duration: Double
    public var importedAt: Date

    public init(id: Int64? = nil, language: String, title: String, contentHash: String,
                videoPath: String, audioPath: String? = nil, duration: Double, importedAt: Date = Date()) {
        self.id = id; self.language = language; self.title = title; self.contentHash = contentHash
        self.videoPath = videoPath; self.audioPath = audioPath; self.duration = duration
        self.importedAt = importedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Subtitle: LangRecord {
    public static let databaseTableName = "subtitles"
    public var id: Int64?
    public var videoId: Int64
    public var idx: Int
    public var startTime: Double
    public var endTime: Double
    public var text: String

    public init(id: Int64? = nil, videoId: Int64, idx: Int, startTime: Double, endTime: Double, text: String) {
        self.id = id; self.videoId = videoId; self.idx = idx
        self.startTime = startTime; self.endTime = endTime; self.text = text
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Word: LangRecord {
    public static let databaseTableName = "words"
    public var id: Int64?
    public var language: String
    public var lemma: String
    public var pos: PartOfSpeech
    public var status: WordStatus
    public var stage: SRSStage?
    public var nextReview: Date?

    public init(id: Int64? = nil, language: String, lemma: String, pos: PartOfSpeech,
                status: WordStatus = .new, stage: SRSStage? = nil, nextReview: Date? = nil) {
        self.id = id; self.language = language; self.lemma = lemma; self.pos = pos
        self.status = status; self.stage = stage; self.nextReview = nextReview
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Occurrence: LangRecord {
    public static let databaseTableName = "occurrences"
    public var id: Int64?
    public var wordId: Int64
    public var subtitleId: Int64
    public var surface: String

    public init(id: Int64? = nil, wordId: Int64, subtitleId: Int64, surface: String) {
        self.id = id; self.wordId = wordId; self.subtitleId = subtitleId; self.surface = surface
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct DictionaryEntry: LangRecord {
    public static let databaseTableName = "dictionary"
    public var id: Int64?
    public var language: String
    public var headword: String
    public var reading: String?
    public var gloss: String

    public init(id: Int64? = nil, language: String, headword: String, reading: String? = nil, gloss: String) {
        self.id = id; self.language = language; self.headword = headword
        self.reading = reading; self.gloss = gloss
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension DictionaryEntry: Identifiable {}

extension Video: Identifiable {}
