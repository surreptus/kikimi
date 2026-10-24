import AppKit
import LangCore
import SwiftUI

/// Saving your progress to a `.reprise` file and restoring it, and where that has got to, for the Data settings.
/// The work is in LangCore; this holds the steps a person sees: choose, preview, confirm, done.
@MainActor @Observable
final class BackupModel {
    enum Request { case export, chooseFile }

    struct Pending {
        let url: URL
        let data: Data
        let preview: BackupPreview
    }

    enum State {
        case idle
        case working
        case exported(URL, words: Int)
        case previewing(Pending)
        case restored(ProgressImportReport, settingsRestored: Bool)
        case failed(String)
    }

    var state: State = .idle
    var includeSettings = true
    /// Set by the File menu; the Data settings carry it out when they show.
    var request: Request?

    /// The settings the app itself keeps that a backup may carry. A file can set these and nothing else.
    static let appSettingKeys: Set<String> = [Appearance.key, "highlightWords", "language"]

    // MARK: Save

    func export(env: LangEnvironment) async {
        let name = "Reprise progress \(Date().formatted(.iso8601.year().month().day()))"
        guard let url = ExportPanels.saveFile(suggestedName: name, fileExtension: ProgressBackup.fileExtension) else { return }
        state = .working
        do {
            let data = try await env.makeBackup(extraSettings: Self.currentAppSettings())
            try data.write(to: url, options: .atomic)
            state = .exported(url, words: try ProgressBackup.decode(data).words.count)
        } catch {
            state = .failed("Couldn't save the backup: \(error.localizedDescription)")
        }
    }

    // MARK: Restore

    func chooseFile(env: LangEnvironment) async {
        guard let url = ExportPanels.openFile(fileExtension: ProgressBackup.fileExtension) else { return }
        await open(url, env: env)
    }

    /// Reads a file and shows what restoring it would do. Nothing changes until `restore`.
    func open(_ url: URL, env: LangEnvironment) async {
        state = .working
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let preview = try await env.previewBackup(data, appSettingKeys: Self.appSettingKeys)
            state = .previewing(Pending(url: url, data: data, preview: preview))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restore(env: LangEnvironment, app: AppState) async {
        guard case .previewing(let pending) = state else { return }
        state = .working
        do {
            let result = try await env.restoreBackup(
                pending.data, includingSettings: includeSettings, appSettingKeys: Self.appSettingKeys)
            apply(result.appSettings, to: app)
            app.dataChanged()
            state = .restored(result.report, settingsRestored: includeSettings && pending.preview.settingsCount > 0)
        } catch {
            state = .failed("Couldn't restore the backup: \(error.localizedDescription)")
        }
    }

    func reset() { state = .idle }

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
