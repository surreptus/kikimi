import AppKit
import LangCore
import SwiftUI

/// Saving your progress to a `.aomame` file and restoring it, and where that has got to, for the Data settings.
/// The work is in LangCore; this holds the steps a person sees: choose, preview, confirm, done.
@MainActor @Observable
final class BackupModel {
    enum Request { case export, chooseFile }

    struct Pending {
        let url: URL
        let data: Data
        let preview: BackupPreview
        /// Set when `url` is a full backup folder: what it would do with the videos.
        var full: FullBackupPreview?
    }

    enum State {
        case idle
        case working
        case exported(URL, words: Int, videos: Int)
        case previewing(Pending)
        case restored(ProgressImportReport, settingsRestored: Bool, videos: Int)
        case failed(String)
    }

    var state: State = .idle
    var includeSettings = true
    /// Also save each video's compressed copy and transcript, in a folder.
    var includeVideos = false
    /// Access to a dropped or chosen folder is kept until the restore is over.
    private var scopedURL: URL?
    /// Set by the File menu; the Data settings carry it out when they show.
    var request: Request?

    /// The settings the app itself keeps that a backup may carry. A file can set these and nothing else.
    static let appSettingKeys: Set<String> = [Appearance.key, "highlightWords", "language"]

    // MARK: Save

    func export(env: LangEnvironment) async {
        if includeVideos { await exportFolder(env: env); return }
        let name = "Aomame progress \(Date().formatted(.iso8601.year().month().day()))"
        guard let url = ExportPanels.saveFile(suggestedName: name, fileExtension: ProgressBackup.fileExtension) else { return }
        state = .working
        do {
            let data = try await env.makeBackup(extraSettings: Self.currentAppSettings())
            try data.write(to: url, options: .atomic)
            state = .exported(url, words: try ProgressBackup.decode(data).words.count, videos: 0)
        } catch {
            state = .failed(String(localized: "Couldn't save the backup: \(error.localizedDescription)"))
        }
    }

    /// A folder with the progress file, every transcript and the compressed videos.
    private func exportFolder(env: LangEnvironment) async {
        guard let parent = ExportPanels.chooseFolder(message: String(localized: "Choose where to save the backup folder")) else { return }
        state = .working
        do {
            let name = "Aomame backup \(Date().formatted(.iso8601.year().month().day()))"
            let summary = try await env.writeFullBackup(in: parent, name: name, extraSettings: Self.currentAppSettings())
            state = .exported(summary.folder, words: summary.words, videos: summary.videos)
        } catch {
            state = .failed(String(localized: "Couldn't save the backup: \(error.localizedDescription)"))
        }
    }

    // MARK: Restore

    func chooseFile(env: LangEnvironment) async {
        guard let url = ExportPanels.openBackup() else { return }
        await open(url, env: env)
    }

    /// Reads a file and shows what restoring it would do. Nothing changes until `restore`.
    func open(_ url: URL, env: LangEnvironment) async {
        state = .working
        stopAccess()
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        do {
            if LangEnvironment.isFullBackup(url) {
                let full = try await env.previewFullBackup(at: url, appSettingKeys: Self.appSettingKeys)
                let data = try Data(contentsOf: url.appending(path: LangEnvironment.progressFileName))
                state = .previewing(Pending(url: url, data: data, preview: full.progress, full: full))
            } else {
                let data = try Data(contentsOf: url)
                let preview = try await env.previewBackup(data, appSettingKeys: Self.appSettingKeys)
                state = .previewing(Pending(url: url, data: data, preview: preview))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restore(env: LangEnvironment, app: AppState) async {
        guard case .previewing(let pending) = state else { return }
        state = .working
        do {
            let settingsRestored = includeSettings && pending.preview.settingsCount > 0
            if pending.full != nil {
                let result = try await env.restoreFullBackup(
                    from: pending.url, includingSettings: includeSettings, appSettingKeys: Self.appSettingKeys)
                apply(result.appSettings, to: app)
                app.dataChanged()
                state = .restored(result.report, settingsRestored: settingsRestored, videos: result.videosAdded)
            } else {
                let result = try await env.restoreBackup(
                    pending.data, includingSettings: includeSettings, appSettingKeys: Self.appSettingKeys)
                apply(result.appSettings, to: app)
                app.dataChanged()
                state = .restored(result.report, settingsRestored: settingsRestored, videos: 0)
            }
            stopAccess()
        } catch {
            state = .failed(String(localized: "Couldn't restore the backup: \(error.localizedDescription)"))
        }
    }

    func reset() { stopAccess(); state = .idle }

    private func stopAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    // MARK: The app's own settings

    static func currentAppSettings() -> [String: String] {
        let defaults = UserDefaults.standard
        var settings: [String: String] = [:]
        settings[Appearance.key] = defaults.string(forKey: Appearance.key) ?? Appearance.system.rawValue
        settings["highlightWords"] = (defaults.object(forKey: "highlightWords") as? Bool ?? true) ? "true" : "false"
        if let language = defaults.string(forKey: "language") { settings["language"] = language }
        return settings
    }

    /// Applies only values that make sense; anything else in a file is ignored.
    private func apply(_ settings: [String: String], to app: AppState) {
        let defaults = UserDefaults.standard
        if let value = settings[Appearance.key], Appearance(rawValue: value) != nil { defaults.set(value, forKey: Appearance.key) }
        if let value = settings["highlightWords"], value == "true" || value == "false" { defaults.set(value == "true", forKey: "highlightWords") }
        if let value = settings["language"], LanguageProfiles.profile(for: value) != nil { app.languageCode = value }
    }
}
