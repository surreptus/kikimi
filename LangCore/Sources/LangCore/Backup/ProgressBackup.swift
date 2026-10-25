import Foundation

/// What you've learned, as one file you can keep or move to another Mac: each word that isn't new (its status,
/// stage and next review) and a few settings. It does not hold videos or models; videos are added again, and the
/// words you restored attach to them. The file is plain JSON with the extension `.reprise`, so you can read it.
public struct ProgressBackup: Codable, Equatable, Sendable {
    public static let format = "reprise-progress"
    public static let currentVersion = 1
    public static let fileExtension = "reprise"

    public var format: String
    public var version: Int
    public var createdAt: Date
    public var words: [Entry]
    /// Settings the app chose to include, as text. Keys that aren't known are ignored on restore.
    public var settings: [String: String]

    public struct Entry: Codable, Equatable, Sendable {
        public var language: String
        public var lemma: String
        public var pos: String
        public var status: String
        public var stage: Int?
        public var nextReview: Date?

        public init(language: String, lemma: String, pos: String, status: String, stage: Int? = nil, nextReview: Date? = nil) {
            self.language = language; self.lemma = lemma; self.pos = pos
            self.status = status; self.stage = stage; self.nextReview = nextReview
        }
    }

    public init(createdAt: Date = Date(), words: [Entry], settings: [String: String] = [:]) {
        format = Self.format
        version = Self.currentVersion
        self.createdAt = createdAt
        self.words = words
        self.settings = settings
    }

    // MARK: Reading and writing the file

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Reads and checks a file. Throws a `BackupError` that says what is wrong, in words a person can use.
    public static func decode(_ data: Data) throws -> ProgressBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Check it is one of ours before judging the rest, so a random JSON file gets "not a backup".
        guard let header = try? decoder.decode(Header.self, from: data), header.format == Self.format else {
            throw BackupError.notABackup
        }
        guard header.version <= Self.currentVersion else { throw BackupError.newerVersion(header.version) }
        do { return try decoder.decode(ProgressBackup.self, from: data) }
        catch { throw BackupError.damaged }
    }

    private struct Header: Decodable { let format: String; let version: Int }
}

public enum BackupError: Error, LocalizedError, Equatable {
    case notABackup
    case newerVersion(Int)
    case damaged

    public var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "This file isn't a Reprise backup.", bundle: .module)
        case .newerVersion: String(localized: "This backup was made by a newer version of Reprise. Update the app, then try again.", bundle: .module)
        case .damaged: String(localized: "This backup file is damaged, so nothing was changed.", bundle: .module)
        }
    }
}

/// What importing a backup does (or did), in counts.
public struct ProgressImportReport: Equatable, Sendable {
    /// Words already here as new, which take the backup's progress.
    public var restored = 0
    /// Words not in this library yet: added with their progress, and attached to their sentences when the videos
    /// that contain them are added.
    public var added = 0
    /// Words that already have progress here that differs from the backup. These are left as they are.
    public var kept = 0
    /// Words whose progress here already matches the backup.
    public var unchanged = 0
    /// Entries that couldn't be used: a language this version doesn't have, or a value it doesn't understand.
    public var skipped = 0

    public var changes: Int { restored + added }
    public init() {}
}
