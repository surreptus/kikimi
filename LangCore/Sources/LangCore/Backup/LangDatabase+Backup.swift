import Foundation
import GRDB

extension LangDatabase {
    /// Every word you have done something with. Words that are still new aren't written: they come back by
    /// themselves when the videos are added again.
    public func exportProgress(settings: [String: String] = [:], now: Date = Date()) async throws -> ProgressBackup {
        let words = try await writer.read { db in
            try Word.filter(Column("status") != WordStatus.new.rawValue)
                .order(Column("language"), Column("lemma"), Column("pos"))
                .fetchAll(db)
        }
        let entries = words.map {
            ProgressBackup.Entry(
                language: $0.language, lemma: $0.lemma, pos: $0.pos.rawValue, status: $0.status.rawValue,
                stage: $0.stage?.rawValue, nextReview: $0.nextReview)
        }
        return ProgressBackup(createdAt: now, words: entries, settings: settings)
    }

    /// What importing `backup` would do, without changing anything.
    public func previewProgressImport(_ backup: ProgressBackup, now: Date = Date()) async throws -> ProgressImportReport {
        try await writer.read { db in try Self.plan(backup, in: db, now: now).report }
    }

    /// Applies a backup. Safe to run twice, and it never overwrites progress you already have here: a word that is
    /// still new takes the backup's status; a word you have already worked on is kept.
    @discardableResult
    public func importProgress(_ backup: ProgressBackup, now: Date = Date()) async throws -> ProgressImportReport {
        try await writer.write { db in
            let plan = try Self.plan(backup, in: db, now: now)
            for update in plan.updates {
                var word = update.word
                try word.save(db)
            }
            return plan.report
        }
    }

    // MARK: Working out what to do

    private struct Plan {
        var report = ProgressImportReport()
        var updates: [(word: Word, isNew: Bool)] = []
    }

    private static func plan(_ backup: ProgressBackup, in db: Database, now: Date) throws -> Plan {
        var plan = Plan()
        let languages = Set(LanguageProfiles.all.map(\.code))

        for entry in backup.words {
            guard languages.contains(entry.language),
                  let pos = PartOfSpeech(rawValue: entry.pos),
                  let status = WordStatus(rawValue: entry.status), status != .new,
                  let progress = normalised(status: status, stage: entry.stage, nextReview: entry.nextReview, now: now),
                  !entry.lemma.isEmpty
            else { plan.report.skipped += 1; continue }

            let existing = try Word
                .filter(Column("language") == entry.language && Column("lemma") == entry.lemma && Column("pos") == pos.rawValue)
                .fetchOne(db)

            guard let existing else {
                plan.report.added += 1
                plan.updates.append((Word(language: entry.language, lemma: entry.lemma, pos: pos,
                                          status: status, stage: progress.stage, nextReview: progress.nextReview), true))
                continue
            }
            if existing.status == .new {
                plan.report.restored += 1
                var word = existing
                word.status = status; word.stage = progress.stage; word.nextReview = progress.nextReview
                plan.updates.append((word, false))
            } else if existing.status == status, existing.stage == progress.stage {
                plan.report.unchanged += 1
            } else {
                plan.report.kept += 1
            }
        }
        return plan
    }

    /// The stage and next review a status needs to make sense, or nil if the entry can't be trusted.
    private static func normalised(
        status: WordStatus, stage: Int?, nextReview: Date?, now: Date
    ) -> (stage: SRSStage?, nextReview: Date?)? {
        switch status {
        case .new: return nil
        case .known: return (nil, nil)
        case .burned: return (.burned, nil)
        case .learning:
            // A learning word needs a stage from the first eight, and a date it is due (now, if none was kept).
            guard let stage, let parsed = SRSStage(rawValue: stage), parsed != .burned else { return nil }
            return (parsed, nextReview ?? now)
        }
    }
}
