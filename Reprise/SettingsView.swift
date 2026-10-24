import AppKit
import LangCore
import SwiftUI

/// The tabs of the Settings window, listed down its left side.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case languages = "Languages"
    case data = "Data"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .languages: "globe"
        case .data: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }
}

/// Settings (⌘,), a panel over the main window: a list of tabs on the left and the chosen one on the right.
/// Everything here changes the same stored values the rest of the app uses, so the two places never disagree.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                if case .ready(let env) = app.phase {
                    switch app.settingsTab {
                    case .general: GeneralTab()
                    case .languages: LanguagesTab(env: env)
                    case .data: DataTab(env: env)
                    case .about: AboutTab()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 540)
        .background(Theme.field)
        .tint(Theme.ink)
        .fontDesign(.rounded)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings").font(Theme.title(20)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 14)
            ForEach(SettingsTab.allCases) { tab in
                Button { app.settingsTab = tab } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.symbol).font(.system(size: 15, weight: .medium)).frame(width: 22)
                        Text(tab.rawValue).font(.system(size: 15, weight: .medium, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(app.settingsTab == tab ? Theme.softStrong : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(app.settingsTab == tab ? .isSelected : [])
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.pill(compact: true))
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 6)
        }
        .padding(14)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Theme.rail)
    }
}

// MARK: Page building blocks

/// A tab's page: a title, then its groups.
private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(title).font(Theme.title(30)).foregroundStyle(Theme.ink)
                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A heading, an optional line under it, and what belongs to it.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(17)).foregroundStyle(Theme.ink)
            if let note { Text(note).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            content
        }
    }
}

private func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

// MARK: General

private struct GeneralTab: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some View {
        SettingsPage(title: "General") {
            SettingsGroup(title: "Appearance", note: "Match system follows your Mac's Light or Dark setting.") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
            }
        }
    }
}

// MARK: Languages

private struct LanguagesTab: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    /// Bumped when a preference is written, so the pickers redraw (the preferences aren't observable).
    @State private var refresh = 0

    var body: some View {
        SettingsPage(title: "Languages") {
            Text("A model downloads once, from the Videos page, the first time you need it. The model applies to videos you add from now on; videos already added keep their transcripts.")
                .font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(LanguageProfiles.all, id: \.code) { profile in
                SettingsGroup(title: profile.displayName) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Speech model", selection: modelBinding(profile)) {
                            ForEach(choices(for: profile), id: \.self) { Text(label(for: $0, profile: profile)).tag($0) }
                        }
                        Picker("Sentence audio on review cards", selection: audioBinding(profile)) {
                            ForEach(SentenceAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    .panel()
                }
            }
        }
        .id(refresh)
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
        return ModelCatalog.name(for: variant) + size + (variant == profile.defaultModel ? " (recommended)" : "")
    }
}

// MARK: Data

/// Saving your progress to a file, restoring it, and where the rest of your data is kept.
private struct DataTab: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var backup = app.backup
        SettingsPage(title: "Data") {
            SettingsGroup(
                title: "Back up your progress",
                note: "Saves the words you are learning and the ones you know, with their stages and review dates, to a file. It doesn't include videos or speech models.") {
                    HStack(spacing: 12) {
                        Button("Save backup…") { Task { await app.backup.export(env: env) } }
                            .buttonStyle(.pill)
                            .disabled(isWorking)
                        if case .exported(let url, let words) = backup.state {
                            Text("Saved \(plural(words, "word")).").font(Theme.small).foregroundStyle(Theme.ink)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.pill(.secondary, compact: true))
                        }
                    }
                }

            SettingsGroup(
                title: "Restore from a backup",
                note: "Choose a backup file, or drop one here. You'll see what would change before anything does, and progress you already have is never overwritten.") {
                    restore(backup)
                }

            SettingsGroup(title: "Storage", note: "Speech models and your saved videos are kept on this Mac.") {
                Button("Manage storage…") {
                    app.showSettings = false
                    app.showStorage = true
                }
                .buttonStyle(.pill(.secondary, compact: true))
            }
        }
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
            previewCard(pending, backup)
        case .restored(let report, let settingsRestored):
            card {
                Text("Restored").font(.system(.headline, design: .rounded))
                Text(restoredLine(report) + (settingsRestored ? " Settings restored too." : ""))
                    .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Done") { backup.reset() }.buttonStyle(.pill(compact: true))
            }
        case .failed(let message):
            card {
                Text(message).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { backup.reset() }.buttonStyle(.pill(.secondary, compact: true))
            }
        case .idle, .exported:
            chooser(backup)
        }
    }

    private func chooser(_ backup: BackupModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Choose file…") { Task { await backup.chooseFile(env: env) } }.buttonStyle(.pill(.secondary))
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.soft.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7])))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension == ProgressBackup.fileExtension }) else { return false }
            Task { await backup.open(url, env: env) }
            return true
        }
    }

    private func previewCard(_ pending: BackupModel.Pending, _ backup: BackupModel) -> some View {
        let preview = pending.preview, report = preview.report
        let total = preview.learning + preview.known + preview.burned
        let languages = preview.languages.compactMap { LanguageProfiles.profile(for: $0)?.displayName }.joined(separator: ", ")
        return card {
            Text("Backup from \(preview.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(.headline, design: .rounded))
            Text("\(plural(total, "word")): \(preview.learning) learning, \(preview.known) known, \(preview.burned) finished"
                 + (languages.isEmpty ? "" : " · \(languages)"))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                if report.changes == 0 {
                    Text("Everything in this file is already here, so nothing would change.")
                }
                if report.restored > 0 { Text("• \(plural(report.restored, "word")) here will take the backup's progress.") }
                if report.added > 0 {
                    Text("• \(plural(report.added, "word")) not in your library yet will be added, and join their sentences when you add the videos.")
                }
                if report.kept > 0 { Text("• \(plural(report.kept, "word")) you have already worked on here will be left as they are.") }
                if report.unchanged > 0 { Text("• \(report.unchanged) already match.") }
                if report.skipped > 0 { Text("• \(plural(report.skipped, "entry")) couldn't be read and will be skipped.") }
            }
            .fixedSize(horizontal: false, vertical: true)
            if preview.settingsCount > 0 {
                @Bindable var backup = backup
                Toggle("Also restore the settings in this file", isOn: $backup.includeSettings)
            }
            HStack(spacing: 10) {
                if report.changes > 0 {
                    Button("Restore") { Task { await backup.restore(env: env, app: app) } }.buttonStyle(.pill(compact: true))
                    Button("Cancel") { backup.reset() }.buttonStyle(.pill(.secondary, compact: true))
                } else {
                    Button("Done") { backup.reset() }.buttonStyle(.pill(compact: true))
                }
            }
        }
    }

    private func restoredLine(_ report: ProgressImportReport) -> String {
        var parts: [String] = []
        if report.restored > 0 { parts.append("\(plural(report.restored, "word")) updated") }
        if report.added > 0 { parts.append("\(plural(report.added, "word")) added") }
        if report.kept > 0 { parts.append("\(plural(report.kept, "word")) kept as they were") }
        return parts.isEmpty ? "Nothing needed changing." : parts.joined(separator: ", ") + "."
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .panel(padding: 16)
    }
}

// MARK: About

private struct AboutTab: View {
    @Environment(AppState.self) private var app

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        SettingsPage(title: "About") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reprise").font(Theme.title(24)).foregroundStyle(Theme.ink)
                Text(version).font(Theme.small).foregroundStyle(Theme.muted)
                Text("Learn Spanish or Japanese from videos you own, on your Mac.").foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            SettingsGroup(title: "Read more") {
                HStack(spacing: 10) {
                    link("How it works") { app.showAbout = true }
                    link("Privacy policy") { app.showPrivacy = true }
                    link("Acknowledgements") { app.showAcknowledgements = true }
                }
            }
            SettingsGroup(title: "Open source", note: "Reprise is free software under the MIT licence.") {
                if let url = URL(string: "https://github.com/surreptus/reprise") {
                    Link("github.com/surreptus/reprise", destination: url).foregroundStyle(Theme.ink).underline()
                }
            }
        }
    }

    /// Opens one of the other panels, closing Settings first so they aren't stacked.
    private func link(_ title: String, _ open: @escaping () -> Void) -> some View {
        Button(title) {
            app.showSettings = false
            open()
        }
        .buttonStyle(.pill(.secondary, compact: true))
    }
}

/// Light, Dark, or whatever the Mac is set to. Stored under one key, read by the app and the Settings window.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"
    var title: String {
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
