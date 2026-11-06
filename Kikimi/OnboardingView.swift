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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(LanguageProfiles.all, id: \.code) { profile in
                            LanguageTile(profile: profile, selected: chosen.contains(profile.code)) { toggle(profile) }
                        }
                    }
                }

                Text(TranslationPreferences.isSupported
                     ? String(localized: "Next: add a video you enjoy. Translations stay hidden until you ask for one, so you listen first.")
                     : String(localized: "Next: add a video you enjoy."))
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

    private func toggle(_ profile: any LanguageProfile) {
        if chosen.contains(profile.code) { chosen.remove(profile.code) } else { chosen.insert(profile.code) }
    }
}

/// One language to learn: its flag, its own name large and its name in your language beneath. Several can be chosen;
/// a tick (not only the fill) says which.
private struct LanguageTile: View {
    let profile: any LanguageProfile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if let region = profile.flagRegion { Flag(region: region) }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.ink : Theme.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.nativeName).font(Theme.title(22))
                    if profile.displayName != profile.nativeName {
                        Text(profile.displayName).font(Theme.small).foregroundStyle(Theme.muted)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(selected ? Theme.softStrong : Theme.soft))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Theme.ink.opacity(selected ? 0.8 : 0), lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.displayName == profile.nativeName ? profile.displayName : "\(profile.nativeName), \(profile.displayName)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
