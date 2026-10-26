import AppKit
import LangCore
import SwiftUI

/// The tabs of the Settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case languages = "Languages"
    case data = "Data"
    case about = "About"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .languages: "Languages"
        case .data: "Data"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .languages: "globe"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
}

/// The Settings window (⌘,). It is deliberately an ordinary Mac settings window, with icon tabs along the top and
/// grouped forms, so it looks like the settings of every other app. Everything here changes the same stored values
/// the rest of the app uses, so the two places never disagree.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some View {
        Group {
            if case .ready(let env) = app.phase {
                TabView(selection: Bindable(app).settingsTab) {
                    GeneralTab()
                        .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }
                        .tag(SettingsTab.general)
                    LanguagesTab(env: env)
                        .tabItem { Label(SettingsTab.languages.title, systemImage: SettingsTab.languages.symbol) }
                        .tag(SettingsTab.languages)
                    DataTab(env: env)
                        .tabItem { Label(SettingsTab.data.title, systemImage: SettingsTab.data.symbol) }
                        .tag(SettingsTab.data)
                    AboutTab()
                        .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }
                        .tag(SettingsTab.about)
                }
            } else {
                ProgressView().frame(width: 480, height: 200)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}


// MARK: General

private struct GeneralTab: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @AppStorage(TranscriptSize.key) private var transcriptSize = TranscriptSize.standard
    @AppStorage(VideoQualityPreference.key) private var videoQuality = VideoQuality.smallest.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Match system follows your Mac's Light or Dark setting.")
            }
            Section {
                Picker("Transcript text", selection: $transcriptSize) {
                    ForEach(TranscriptSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("日本語 · Una frase de ejemplo")
                    .font(.system(size: transcriptSize.points, design: .rounded))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)   // a preview of the size, not content
            } footer: {
                Text("The size of the subtitle lines beside the video.")
            }
            Section {
                Picker("Video quality", selection: $videoQuality) {
                    Text("Smallest size (recommended)").tag(VideoQuality.smallest.rawValue)
                    Text("Original quality").tag(VideoQuality.original.rawValue)
                }
            } footer: {
                Text("The copy Kikimi keeps of each video you add. Smallest compresses it (in our tests a 161 MB video became 29 MB), which is plenty to follow along and study from. Original quality keeps your file exactly as it is: the best picture and sound, but the same size. Your own files are never changed either way, and this applies to videos you add from now on.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 470)
    }
}

// MARK: Languages

private struct LanguagesTab: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    /// Bumped when a preference is written, so the pickers redraw (the preferences aren't observable).
    @State private var refresh = 0

    var body: some View {
        Form {
            ForEach(LanguageProfiles.all, id: \.code) { profile in
                Section(profile.displayName) {
                    Picker("Speech model", selection: modelBinding(profile)) {
                        ForEach(choices(for: profile), id: \.self) { Text(label(for: $0, profile: profile)).tag($0) }
                    }
                    Picker("Sentence audio on review cards", selection: audioBinding(profile)) {
                        ForEach(SentenceAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            Section {} footer: {
                Text("A model downloads once, from the Videos page, the first time you need it. It applies to videos you add from now on; videos already added keep their transcripts.")
            }
        }
        .formStyle(.grouped)
        .id(refresh)
        .frame(width: 520, height: 400)
    }

    private func modelBinding(_ profile: any LanguageProfile) -> Binding<String> {
        Binding(
            get: { env.preferences.model(for: profile) },
            set: {
                env.preferences.setModel($0 == profile.defaultModel ? nil : $0, for: profile)
                refresh += 1
                app.dataChanged()   // so the Videos page re-reads its model choice
            })
    }

    private func audioBinding(_ profile: any LanguageProfile) -> Binding<SentenceAudioMode> {
        Binding(
            get: { env.reviewAudio.mode(for: profile) },
            set: { env.reviewAudio.setMode($0, for: profile); refresh += 1 })
    }

    private func choices(for profile: any LanguageProfile) -> [String] {
        let all = ModelPreferences.choices
        return all.contains(profile.defaultModel) ? all : [profile.defaultModel] + all
    }

    /// "medium · 1.5 GB (recommended)".
    private func label(for variant: String, profile: any LanguageProfile) -> String {
        let size = ModelCatalog.info(for: variant)
            .map { " · " + ByteCountFormatter.string(fromByteCount: $0.downloadBytes, countStyle: .file) } ?? ""
        return ModelCatalog.name(for: variant) + size + (variant == profile.defaultModel ? String(localized: " (recommended)") : "")
    }
}

// MARK: Data

/// Saving your progress to a file, restoring it, and where the rest of your data is kept.
private struct DataTab: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var known: KnownListState = .idle
    @State private var libraryBytes: Int64 = 0

    var body: some View {
        @Bindable var backup = app.backup
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Include my videos and transcripts", isOn: $backup.includeVideos)
                    HStack(spacing: 12) {
                        Button("Save backup…") { Task { await app.backup.export(env: env) } }
                            .disabled(isWorking)
                        if case .exported(let url, let words, let videos) = backup.state {
                            Text(videos > 0
                                 ? inflected("Saved ^[\(words) word](inflect: true) and ^[\(videos) video](inflect: true).")
                                 : inflected("Saved ^[\(words) word](inflect: true)."))
                                .foregroundStyle(.secondary)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                }
            } header: {
                Text("Back up your progress")
            } footer: {
                Text(backup.includeVideos
                     ? "Saves a folder with your progress, each video's transcript and its compressed copy (about \(ByteCountFormatter.string(fromByteCount: libraryBytes, countStyle: .file)) in all), so a new Mac needs no re-transcribing. Speech models aren't included; download them again."
                     : "Saves the words you are learning and the ones you know, with their stages and review dates, to a small file. Turn on the option above to include your videos and transcripts too. Speech models are never included.")
            }

            Section {
                restore(backup)
            } header: {
                Text("Restore from a backup")
            } footer: {
                Text("Choose a backup file or folder, or drop one on this window. You'll see what would change before anything does, and progress and videos you already have are never overwritten.")
            }

            Section {
                knownListContent
            } header: {
                Text("Words you already know")
            } footer: {
                Text("Choose a text file of \(app.profile.displayName) words you know, one per line (or the first column of a CSV, such as an Anki export). They're marked known, so each video's coverage reflects what you can really follow. Only words already in your library change; to do another language, switch it in the sidebar first.")
            }

            Section {
                Button("Manage storage…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    app.showStorage = true
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Speech models and your saved videos are kept on this Mac.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension == ProgressBackup.fileExtension || LangEnvironment.isFullBackup($0) })
            else { return false }
            Task { await app.backup.open(url, env: env) }
            return true
        }
        .task { libraryBytes = env.libraryBytes() }
        // The File menu's Export and Import items land here and ask for the action.
        .task(id: app.backup.request) {
            guard let request = app.backup.request else { return }
            app.backup.request = nil
            switch request {
            case .export: await app.backup.export(env: env)
            case .chooseFile: await app.backup.chooseFile(env: env)
            }
        }
    }

    private var isWorking: Bool {
        if case .working = app.backup.state { return true }
        return false
    }

    @ViewBuilder
    private func restore(_ backup: BackupModel) -> some View {
        switch backup.state {
        case .working:
            ProgressView().controlSize(.small)
        case .previewing(let pending):
            previewContent(pending, backup)
        case .restored(let report, let settingsRestored, let videos):
            VStack(alignment: .leading, spacing: 8) {
                Text("Restored").font(.headline)
                Text((videos > 0 ? inflected("^[\(videos) video](inflect: true) added. ") : "")
                     + restoredLine(report) + (settingsRestored ? " Settings restored too." : ""))
                    .foregroundStyle(.secondary)
                Button("Done") { backup.reset() }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { backup.reset() }
            }
        case .idle, .exported:
            Button("Choose file…") { Task { await backup.chooseFile(env: env) } }
        }
    }

    private func previewContent(_ pending: BackupModel.Pending, _ backup: BackupModel) -> some View {
        let preview = pending.preview, report = preview.report
        let total = preview.learning + preview.known + preview.finished
        let languages = preview.languages.compactMap { LanguageProfiles.profile(for: $0)?.displayName }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 8) {
            Text("Backup from \(preview.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.headline)
            Text("^[\(total) word](inflect: true): \(preview.learning) learning, \(preview.known) known, \(preview.finished) finished"
                 + (languages.isEmpty ? "" : " · \(languages)"))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                if report.changes == 0 && (pending.full?.videosToAdd ?? 0) == 0 {
                    Text("Everything in this file is already here, so nothing would change.")
                }
                if let full = pending.full {
                    if full.videosToAdd > 0 {
                        Text("• ^[\(full.videosToAdd) video](inflect: true) will be added (\(ByteCountFormatter.string(fromByteCount: full.bytesToCopy, countStyle: .file))), with transcripts and words.")
                    }
                    if full.videosAlreadyHere > 0 { Text("• ^[\(full.videosAlreadyHere) video](inflect: true) already here will be left as they are.") }
                    if full.videosMissingFiles > 0 { Text("• ^[\(full.videosMissingFiles) video](inflect: true) can't be restored: the files are missing from the folder.") }
                }
                if report.restored > 0 { Text("• ^[\(report.restored) word](inflect: true) here will take the backup's progress.") }
                if report.added > 0 {
                    Text("• ^[\(report.added) word](inflect: true) not in your library yet will be added, and join their sentences when you add the videos.")
                }
                if report.kept > 0 { Text("• ^[\(report.kept) word](inflect: true) you have already worked on here will be left as they are.") }
                if report.unchanged > 0 { Text("• \(report.unchanged) already match.") }
                if report.skipped > 0 { Text("• ^[\(report.skipped) entry](inflect: true) couldn't be read and will be skipped.") }
            }
            .fixedSize(horizontal: false, vertical: true)
            if preview.settingsCount > 0 {
                @Bindable var backup = backup
                Toggle("Also restore the settings in this file", isOn: $backup.includeSettings)
            }
            HStack {
                if report.changes > 0 || (pending.full?.videosToAdd ?? 0) > 0 {
                    Button("Restore") { Task { await backup.restore(env: env, app: app) } }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { backup.reset() }
                } else {
                    Button("Done") { backup.reset() }
                }
            }
        }
    }

    // MARK: Words you already know

    private enum KnownListState {
        case idle
        case previewing(words: [String], report: KnownListReport)
        case done(KnownListReport)
        case failed(String)
    }

    @ViewBuilder
    private var knownListContent: some View {
        switch known {
        case .idle:
            Button("Choose word list…") { Task { await chooseKnownList() } }
        case .previewing(let words, let report):
            VStack(alignment: .leading, spacing: 8) {
                Text("^[\(report.listed) word](inflect: true) in the list").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    if report.marked > 0 {
                        Text("• ^[\(report.marked) word](inflect: true) in your \(app.profile.displayName) library will be marked known."
                             + (report.fromLearning > 0 ? " \(report.fromLearning) of them are being learned, and leave your reviews." : ""))
                    }
                    if report.alreadyKnown > 0 { Text("• \(report.alreadyKnown) are already known.") }
                    if report.notInLibrary > 0 {
                        Text("• \(report.notInLibrary) aren't in your library yet, so there's nothing to change; they'll be new when they appear in a video.")
                    }
                    if report.marked == 0 { Text("Nothing in this list would change.") }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if report.marked > 0 {
                        Button("Mark as known") { Task { await applyKnownList(words) } }.keyboardShortcut(.defaultAction)
                        Button("Cancel") { known = .idle }
                    } else {
                        Button("Done") { known = .idle }
                    }
                }
            }
        case .done(let report):
            VStack(alignment: .leading, spacing: 8) {
                Text("Marked ^[\(report.marked) word](inflect: true) as known.").font(.headline)
                Button("Done") { known = .idle }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { known = .idle }
            }
        }
    }

    private func chooseKnownList() async {
        guard let url = ExportPanels.openTextFile() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let words = KnownWordList.parse(text)
            guard !words.isEmpty else { known = .failed(String(localized: "That file has no words in it.")); return }
            let report = try await env.database.markKnown(lemmas: words, language: app.languageCode, dryRun: true)
            known = .previewing(words: words, report: report)
        } catch {
            known = .failed(String(localized: "Couldn't read that file as text: \(error.localizedDescription)"))
        }
    }

    private func applyKnownList(_ words: [String]) async {
        do {
            let report = try await env.database.markKnown(lemmas: words, language: app.languageCode)
            app.dataChanged()
            known = .done(report)
        } catch {
            known = .failed(String(localized: "Couldn't mark those words: \(error.localizedDescription)"))
        }
    }

    private func restoredLine(_ report: ProgressImportReport) -> String {
        var parts: [String] = []
        if report.restored > 0 { parts.append(inflected("^[\(report.restored) word](inflect: true) updated")) }
        if report.added > 0 { parts.append(inflected("^[\(report.added) word](inflect: true) added")) }
        if report.kept > 0 { parts.append(inflected("^[\(report.kept) word](inflect: true) kept as they were")) }
        return parts.isEmpty ? String(localized: "Nothing needed changing.") : listed(parts) + "."
    }
}

// MARK: About

private struct AboutTab: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Kikimi", value: "Version \(version)")
                Text("Learn Spanish or Japanese from videos you own, on your Mac.").foregroundStyle(.secondary)
            }
            Section("Read more") {
                Button("How Kikimi works") { inMainWindow { app.showAbout = true } }
                Button("Privacy policy") { inMainWindow { app.showPrivacy = true } }
                Button("Terms of use") { inMainWindow { app.showTerms = true } }
                Button("Acknowledgements") { inMainWindow { app.showAcknowledgements = true } }
            }
            Section {
                if let url = URL(string: "https://github.com/surreptus/kikimi") {
                    Link("github.com/surreptus/kikimi", destination: url)
                }
            } header: {
                Text("Open source")
            } footer: {
                Text("Kikimi is free software under the MIT licence.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }

    /// Those panels belong to the main window, so bring it forward and open them there.
    private func inMainWindow(_ action: () -> Void) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        action()
    }
}

/// Light, Dark, or whatever the Mac is set to. Stored under one key, read by the app and the Settings window.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"
    var title: LocalizedStringKey {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
