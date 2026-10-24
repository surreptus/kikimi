import Foundation

/// What a backup file would do, for the preview before anything is changed.
public struct BackupPreview: Equatable, Sendable {
    public var createdAt: Date
    public var learning = 0
    public var known = 0
    public var burned = 0
    public var languages: [String] = []
    public var report: ProgressImportReport
    /// How many of the file's settings this version can use.
    public var settingsCount: Int
}

extension LangEnvironment {
    /// The settings `LangCore` owns, for a backup: the speech model and sentence audio for each language.
    public func backupSettings() -> [String: String] {
        var settings: [String: String] = [:]
        for profile in LanguageProfiles.all {
            settings["whisperModel.\(profile.code)"] = preferences.model(for: profile)
            settings["sentenceAudio.\(profile.code)"] = reviewAudio.mode(for: profile).rawValue
        }
        return settings
    }

    /// The backup file's contents, ready to write. `extraSettings` are the ones the app itself keeps (appearance).
    public func makeBackup(extraSettings: [String: String] = [:]) async throws -> Data {
        let settings = backupSettings().merging(extraSettings) { mine, _ in mine }
        return try await database.exportProgress(settings: settings).encoded()
    }

    /// Reads a file and says what restoring it would change. Nothing is written.
    public func previewBackup(_ data: Data, appSettingKeys: Set<String> = []) async throws -> BackupPreview {
        let backup = try ProgressBackup.decode(data)
        let report = try await database.previewProgressImport(backup)
        var preview = BackupPreview(
            createdAt: backup.createdAt, report: report, settingsCount: validSettings(in: backup, appKeys: appSettingKeys).count)
        for entry in backup.words {
            switch entry.status {
            case WordStatus.learning.rawValue: preview.learning += 1
            case WordStatus.known.rawValue: preview.known += 1
            case WordStatus.burned.rawValue: preview.burned += 1
            default: break
            }
        }
        preview.languages = Array(Set(backup.words.map(\.language))).sorted()
        return preview
    }

    /// Restores progress, and (if asked) the settings that were in the file. Returns what changed, plus the settings
    /// the app should apply itself (those `LangCore` doesn't own).
    @discardableResult
    public func restoreBackup(
        _ data: Data, includingSettings: Bool, appSettingKeys: Set<String> = []
    ) async throws -> (report: ProgressImportReport, appSettings: [String: String]) {
        let backup = try ProgressBackup.decode(data)
        let report = try await database.importProgress(backup)
        var appSettings: [String: String] = [:]
        if includingSettings {
            for (key, value) in validSettings(in: backup, appKeys: appSettingKeys) {
                if let (language, kind) = Self.parseSettingKey(key) { applySetting(kind, language: language, value: value) }
                else { appSettings[key] = value }
            }
        }
        return (report, appSettings)
    }

    // MARK: Settings

    private enum SettingKind { case model, audio }

    private static func parseSettingKey(_ key: String) -> (language: String, kind: SettingKind)? {
        for (prefix, kind) in [("whisperModel.", SettingKind.model), ("sentenceAudio.", .audio)] where key.hasPrefix(prefix) {
            return (String(key.dropFirst(prefix.count)), kind)
        }
        return nil
    }

    /// The file's settings that make sense here: a known language, and a model or mode that exists. A file can't
    /// set anything else: the app names the few keys of its own it allows (`appKeys`), and the rest are ignored.
    private func validSettings(in backup: ProgressBackup, appKeys: Set<String>) -> [String: String] {
        backup.settings.filter { key, value in
            guard let (language, kind) = Self.parseSettingKey(key) else { return appKeys.contains(key) }
            guard LanguageProfiles.profile(for: language) != nil else { return false }
            switch kind {
            case .model: return ModelPreferences.choices.contains(value)
            case .audio: return SentenceAudioMode(rawValue: value) != nil
            }
        }
    }

    private func applySetting(_ kind: SettingKind, language: String, value: String) {
        guard let profile = LanguageProfiles.profile(for: language) else { return }
        switch kind {
        case .model: preferences.setModel(value == profile.defaultModel ? nil : value, for: profile)
        case .audio: if let mode = SentenceAudioMode(rawValue: value) { reviewAudio.setMode(mode, for: profile) }
        }
    }
}
