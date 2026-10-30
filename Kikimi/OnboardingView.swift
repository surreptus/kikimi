import LangCore
import SwiftUI

/// Shown once, before anything else: which languages you are learning. Nothing here is permanent; Settings changes it,
/// and the speech model is offered on the Videos page, where it is needed.
struct OnboardingView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var chosen: Set<String> = []

    private var chosenProfiles: [any LanguageProfile] { LanguageProfiles.all.filter { chosen.contains($0.code) } }

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

                Text("Translations stay hidden until you ask for one, so you listen first. Next: add a video you own.")
                    .font(Theme.small).foregroundStyle(Theme.muted)

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
    }

    private func binding(for profile: any LanguageProfile) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(profile.code) },
            set: { if $0 { chosen.insert(profile.code) } else { chosen.remove(profile.code) } })
    }
}
