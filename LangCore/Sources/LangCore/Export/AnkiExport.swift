import Foundation
import GRDB

/// One note for Anki: a word on the front, its meaning and a sentence from your videos on the back.
public struct AnkiCard: Equatable, Sendable {
    /// Stable for a word, so importing the file again updates the note instead of adding a duplicate.
    public var guid: String
    public var front: String
    public var back: String
    public var tags: [String]

    public init(guid: String, front: String, back: String, tags: [String]) {
        self.guid = guid; self.front = front; self.back = back; self.tags = tags
    }
}

/// Builds the file Anki imports (File > Import): plain text, tab-separated, with header lines that name the deck,
/// the note type and the columns. No account and nothing leaves the Mac.
public enum AnkiExport {
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escaped for Anki's HTML fields, with line breaks kept.
    static func html(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }

    /// The sentence with the word as it appears picked out in bold.
    static func sentence(_ text: String, surface: String) -> String {
        guard let range = text.range(of: surface, options: [.caseInsensitive, .diacriticInsensitive]) else { return html(text) }
        return html(String(text[..<range.lowerBound])) + "<b>" + html(String(text[range])) + "</b>"
            + html(String(text[range.upperBound...]))
    }

    public static func card(
        word: Word, reading: String?, gloss: String?, example: ExampleLine?, audioFile: String?
    ) -> AnkiCard {
        var back: [String] = []
        if let reading, !reading.isEmpty, reading != word.lemma { back.append(html(reading)) }
        if let gloss, !gloss.isEmpty { back.append(html(gloss)) }
        if let example {
            back.append("")
            back.append("<i>" + sentence(example.text, surface: example.surface) + "</i>")
            back.append("<small>" + html(example.videoTitle) + "</small>")
            if let audioFile { back.append("[sound:\(audioFile)]") }
        }
        return AnkiCard(
            guid: "aomame:\(word.language):\(word.lemma):\(word.pos.rawValue)",
            front: html(word.lemma), back: back.joined(separator: "<br>"), tags: ["aomame", "aomame_\(word.language)"])
    }

    /// The text of the import file. Fields can't contain tabs or line breaks, so they are turned into spaces and <br>.
    public static func importFile(cards: [AnkiCard], deck: String) -> String {
        func field(_ text: String) -> String {
            text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        var lines = [
            "#separator:tab", "#html:true", "#guid column:1", "#notetype:Basic", "#deck:\(field(deck))", "#tags column:4",
        ]
        for card in cards {
            lines.append([card.guid, card.front, card.back, card.tags.joined(separator: " ")].map(field).joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct AnkiExportResult: Equatable, Sendable {
    public var file: URL
    public var cards: Int
    public var audioFiles: Int
    /// The folder holding the audio, if there is any: its files go in Anki's collection.media folder.
    public var mediaFolder: URL?
}

extension LangDatabase {
    /// The words you are learning in `language`, most-seen first: what is exported when none are chosen.
    public func learningWordIDs(language: String) async throws -> [Int64] {
        try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT words.id FROM words
                LEFT JOIN occurrences ON occurrences.word_id = words.id
                WHERE words.language = ? AND words.status = 'learning'
                GROUP BY words.id ORDER BY COUNT(occurrences.id) DESC, words.lemma
                """, arguments: [language])
        }
    }
}

extension LangEnvironment {
    /// Writes an Anki import file for `wordIDs` into `folder`. With `includeAudio`, each card's example sentence is also
    /// cut from its video as a small audio file in `folder/media`. A word with no example still gets a card.
    public func exportAnki(
        wordIDs: [Int64], language: String, includeAudio: Bool, into folder: URL
    ) async throws -> AnkiExportResult {
        let profile = LanguageProfiles.profile(for: language)
        let mediaFolder = folder.appending(path: "media", directoryHint: .isDirectory)
        var cards: [AnkiCard] = []
        var audioCount = 0

        for id in wordIDs {
            guard let word = try await database.writer.read({ try Word.fetchOne($0, key: id) }) else { continue }
            let entry = try await database.lookup(language: word.language, term: word.lemma, limit: 1).first
            let example = try await database.examples(wordID: id, limit: 1).first

            var audioFile: String?
            if includeAudio, let example, let video = try await database.video(id: example.videoID) {
                try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
                let name = "aomame-\(ClipExporter.sanitized(word.lemma))-\(example.id).m4a"
                do {
                    try await clips.export(video: video, start: example.startTime, end: example.endTime, kind: .audio,
                                           to: mediaFolder.appending(path: name))
                    audioFile = name
                    audioCount += 1
                } catch { audioFile = nil }   // a clip that can't be cut costs the card its audio, not its place
            }
            cards.append(AnkiExport.card(
                word: word, reading: (profile?.display.showsReadings ?? false) ? entry?.reading : nil,
                gloss: entry?.gloss, example: example, audioFile: audioFile))
        }

        let deck = "Aomame \(profile?.displayName ?? language)"
        let file = ClipExporter.uniqueURL(in: folder, base: "aomame-anki-\(language)", ext: "txt")
        try AnkiExport.importFile(cards: cards, deck: deck).write(to: file, atomically: true, encoding: .utf8)
        return AnkiExportResult(file: file, cards: cards.count, audioFiles: audioCount, mediaFolder: audioCount > 0 ? mediaFolder : nil)
    }
}
