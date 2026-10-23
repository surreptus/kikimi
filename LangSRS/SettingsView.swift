import LangCore
import SwiftUI

/// How the app looks, and the speech model and sentence audio for each language. It changes the same stored values
/// the Videos and Review pages use, so the two places never disagree.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    /// Bumped when a preference is written, so the pickers redraw (the preferences aren't observable).
    @State private var refresh = 0

    var body: some View {
        Group {
            if case .ready(let env) = app.phase {
                form(env)
            } else {
                ProgressView().frame(width: 460, height: 200)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    private func form(_ env: LangEnvironment) -> some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Match system follows your Mac's Light or Dark setting.").font(Theme.small).foregroundStyle(Theme.muted)
            }

            Section("Speech model") {
                ForEach(LanguageProfiles.all, id: \.code) { profile in
                    Picker(profile.displayName, selection: modelBinding(profile, env)) {
                        ForEach(choices(for: profile), id: \.self) { Text(label(for: $0, profile: profile)).tag($0) }
                    }
                }
                Text("Used for videos you add from now on. Videos already added keep their transcripts. A model downloads once, from the Videos page.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }

            Section("Sentence audio on review cards") {
                ForEach(LanguageProfiles.all, id: \.code) { profile in
                    Picker(profile.displayName, selection: audioBinding(profile, env)) {
                        ForEach(SentenceAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.field)
        .tint(Theme.ink)
        .fontDesign(.rounded)
        .id(refresh)
        .frame(width: 520)
        .frame(minHeight: 440)
    }

    // MARK: Bindings to the stored preferences

    private func modelBinding(_ profile: any LanguageProfile, _ env: LangEnvironment) -> Binding<String> {
        Binding(
            get: { env.preferences.model(for: profile) },
            set: {
                env.preferences.setModel($0 == profile.defaultModel ? nil : $0, for: profile)
                refresh += 1
                app.dataChanged()   // so the Videos page re-reads its model choice
            })
    }

    private func audioBinding(_ profile: any LanguageProfile, _ env: LangEnvironment) -> Binding<SentenceAudioMode> {
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
