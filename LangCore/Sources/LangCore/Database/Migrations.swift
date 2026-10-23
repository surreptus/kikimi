import GRDB

/// Schema history. Never edit a registered migration; add a new one.
public enum LangMigrations {
    public static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-initial") { db in
            try db.create(table: "videos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("language", .text).notNull()
                t.column("title", .text).notNull()
                t.column("content_hash", .text).notNull().unique()
                t.column("video_path", .text).notNull()
                t.column("audio_path", .text)
                t.column("duration", .double).notNull()
                t.column("imported_at", .datetime).notNull()
            }

            try db.create(table: "subtitles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("video_id", .integer).notNull().references("videos", onDelete: .cascade)
                t.column("idx", .integer).notNull()
                t.column("start_time", .double).notNull()
                t.column("end_time", .double).notNull()
                t.column("text", .text).notNull()
                t.uniqueKey(["video_id", "idx"])
            }

            try db.create(table: "words") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("language", .text).notNull()
                t.column("lemma", .text).notNull()
                t.column("pos", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "new")
                t.column("stage", .integer)
                t.column("next_review", .datetime)
                t.uniqueKey(["language", "lemma", "pos"])
            }
            try db.create(index: "words_language_status", on: "words", columns: ["language", "status"])
            try db.create(index: "words_due", on: "words", columns: ["status", "next_review"])

            try db.create(table: "occurrences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("word_id", .integer).notNull().references("words", onDelete: .cascade)
                t.column("subtitle_id", .integer).notNull().references("subtitles", onDelete: .cascade)
                t.column("surface", .text).notNull()
                t.uniqueKey(["word_id", "subtitle_id"])
            }
            try db.create(index: "occurrences_subtitle", on: "occurrences", columns: ["subtitle_id"])

            try db.create(table: "dictionary") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("language", .text).notNull()
                t.column("headword", .text).notNull()
                t.column("reading", .text)
                t.column("gloss", .text).notNull()
            }
            try db.create(index: "dictionary_lookup", on: "dictionary", columns: ["language", "headword"])
        }

        // Search by kana reading (Japanese).
        migrator.registerMigration("v2-dictionary-reading-index") { db in
            try db.create(index: "dictionary_reading", on: "dictionary", columns: ["language", "reading"])
        }
    }

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        register(in: &migrator)
        return migrator
    }
}
