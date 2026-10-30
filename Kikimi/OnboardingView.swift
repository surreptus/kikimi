import LangCore
import SwiftUI

/// Shown once, before anything else: which languages you are learning, which language you read, and the speech model
/// for each language you chose. Nothing here is permanent; Settings changes every part of it.
struct OnboardingView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var chosen: Set<String> = []
    @AppStorage(TranslationPreferences.targetKey) private var translationTarget = TranslationPreferences.systemLanguage
    @State private var translationLanguages: [TranslationLanguage] = []

    private var chosenProfiles: [any LanguageProfile] { LanguageProfiles.all.filter { chosen.contains($0.code) } }

    /// One entry per model, with the chosen languages that use it: Spanish, French and German share `medium`, so it is
    /// shown and downloaded once, and Japanese's `large-v3` is the only download if it is the only language chosen.
    private var models: [(variant: String, languages: [String])] {
        var order: [String] = []
        var users: [String: [String]] = [:]
        for profile in chosenProfiles {
            let variant = env.preferences.model(for: profile)
            if users[variant] == nil { order.append(variant) }
            users[variant, default: []].append(profile.displayName)
        }
        return order.map { ($0, users[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Kikimi").font(Theme.title(30))
                    Text("Learn a language from videos you own. Everything stays on this Mac.")
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("I'm learning").font(Theme.title(16))
                    ForEach(LanguageProfiles.all, id: \.code) { profile in
                        Toggle(profile.displayName, isOn: binding(for: profile)).toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Translate into").font(Theme.title(16))
                    Picker("Translate into", selection: $translationTarget) {
                        ForEach(translationChoices) { Text($0.name).tag($0.id) }
                    }
                    Text("A line's translation shows only when you ask for it, so you listen first.")
                        .font(Theme.small).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()

                if !chosenProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speech models").font(Theme.title(16))
                        Text("A speech model writes the subtitles for your videos. It downloads once and stays on this Mac. Download it now, or when you add your first video.")
                            .font(Theme.small).foregroundStyle(Theme.muted)
                        ForEach(models, id: \.variant) { model in
                            OnboardingModelRow(env: env, variant: model.variant, languages: model.languages)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }

                HStack {
                    if chosen.isEmpty { Text("Choose at least one language.").font(Theme.small).foregroundStyle(Theme.muted) }
                    Spacer()
                    Button("Start") { app.setLearning(Array(chosen)) }
                        .buttonStyle(.pill)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen.isEmpty)
                }
            }
            .frame(maxWidth: 520)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .task { translationLanguages = await TranslationLanguage.supported() }
    }

    private func binding(for profile: any LanguageProfile) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(profile.code) },
            set: { if $0 { chosen.insert(profile.code) } else { chosen.remove(profile.code) } })
    }

    /// The languages macOS can translate, with the one chosen kept in the list even before the list has loaded.
    private var translationChoices: [TranslationLanguage] {
        translationLanguages.contains { $0.id == translationTarget }
            ? translationLanguages
            : [TranslationLanguage(id: translationTarget, name: Locale.current.localizedString(forIdentifier: translationTarget) ?? translationTarget)] + translationLanguages
    }
}

/// One language's speech model: its size, and a button to download it now.
private struct OnboardingModelRow: View {
    let env: LangEnvironment
    let variant: String
    let languages: [String]

    @State private var installed: Bool?
    @State private var progress: Double?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(listed(languages)).font(.system(.headline, design: .rounded))
                    Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                }
                Spacer()
                if let progress {
                    ProgressView(value: progress).progressViewStyle(ThinProgressStyle()).frame(width: 120)
                        .accessibilityLabel("Downloading the \(ModelCatalog.name(for: variant)) speech model")
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                } else if installed == true {
                    Label("Ready", systemImage: "checkmark").font(.callout).foregroundStyle(Theme.muted)
                } else if installed == false {
                    Button("Download") { Task { await download() } }
                        .buttonStyle(.pill(.secondary, compact: true))
                        .accessibilityLabel("Download the \(ModelCatalog.name(for: variant)) speech model for \(listed(languages))")
                }
            }
            if let error { Text(error).font(Theme.small).foregroundStyle(Theme.red) }
        }
        .task(id: variant) { installed = await env.models.isInstalled(variant) }
    }

    /// "medium · 1.5 GB".
    private var detail: String {
        let size = ModelCatalog.info(for: variant)
            .map { " · " + ByteCountFormatter.string(fromByteCount: $0.downloadBytes, countStyle: .file) } ?? ""
        return ModelCatalog.name(for: variant) + size
    }

    private func download() async {
        error = nil
        progress = 0
        do {
            try await env.models.download(variant: variant) { p in Task { @MainActor in progress = p } }
        } catch {
            self.error = error.localizedDescription
        }
        progress = nil
        installed = await env.models.isInstalled(variant)
    }
}
