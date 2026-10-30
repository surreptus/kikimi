import Foundation
import GRDB

extension LangDatabase {
    /// The translations kept for a video's lines, into `target`, by subtitle id.
    public func translations(videoID: Int64, target: String) async throws -> [Int64: String] {
        try await writer.read { db in
            var result: [Int64: String] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT translations.subtitle_id AS id, translations.text AS text FROM translations
                JOIN subtitles ON subtitles.id = translations.subtitle_id
                WHERE subtitles.video_id = ? AND translations.target = ?
                """, arguments: [videoID, target]) {
                result[row["id"]] = row["text"]
            }
            return result
        }
    }

    /// The kept translations, into `target`, of just these lines.
    public func translations(ids: [Int64], target: String) async throws -> [Int64: String] {
        guard !ids.isEmpty else { return [:] }
        return try await writer.read { db in
            var result: [Int64: String] = [:]
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                for row in try Row.fetchAll(db, sql: "SELECT subtitle_id AS id, text FROM translations WHERE target = ? AND subtitle_id IN (\(marks))",
                                            arguments: StatementArguments([target] + chunk.map { $0 as any DatabaseValueConvertible })) {
                    result[row["id"]] = row["text"]
                }
            }
            return result
        }
    }

    /// Keeps translations (replacing any earlier one for the same line and language).
    public func saveTranslations(_ items: [Int64: String], target: String) async throws {
        guard !items.isEmpty else { return }
        try await writer.write { db in
            for (id, text) in items {
                try db.execute(sql: """
                    INSERT INTO translations (subtitle_id, target, text) VALUES (?, ?, ?)
                    ON CONFLICT (subtitle_id, target) DO UPDATE SET text = excluded.text
                    """, arguments: [id, target, text])
            }
        }
    }
}
