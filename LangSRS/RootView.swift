import LangCore
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Opening your library…").font(Theme.title(18)).foregroundStyle(Theme.ink)
                }
            case .failed(let message):
                ContentUnavailableView("Couldn't start", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready(let env):
                layout(env)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.field)
        .containerBackground(Theme.field, for: .window)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .modal(isPresented: Binding(get: { app.showAcknowledgements }, set: { app.showAcknowledgements = $0 })) { AcknowledgementsView() }
    }

    /// A nav strip fixed to the left edge; the current screen fills the rest of the window.
    private func layout(_ env: LangEnvironment) -> some View {
        @Bindable var app = app
        let selection = Binding<SidebarItem>(
            get: { app.section },
            set: { app.select($0, reduceMotion: reduceMotion) })
        return HStack(spacing: 0) {
            SideNav(
                selection: selection, dueCount: app.dueCount,
                languages: LanguageProfiles.all.map { ($0.code, $0.displayName) },
                language: $app.languageCode, showAbout: { app.showAbout = true }, showPrivacy: { app.showPrivacy = true }, showStorage: { app.showStorage = true },
                showAcknowledgements: { app.showAcknowledgements = true })
            ZStack {
                detail(env: env)
                    .id(app.section)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .modifier(active: ScreenShift(y: app.navDirection * 26, opacity: 0),
                                             identity: ScreenShift(y: 0, opacity: 1)),
                        removal: .opacity))
            }
            .animation(Theme.screenChange(reduceMotion), value: app.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)   // no gap above the content; the title bar has nothing in it
        }
        .modal(isPresented: $app.showStorage) { StorageView(env: env) }
        .modal(isPresented: $app.showAbout) { AboutView() }
        .modal(isPresented: $app.showPrivacy) { PrivacyView() }
    }

    @ViewBuilder
    private func detail(env: LangEnvironment) -> some View {
        switch app.section {
        case .videos: VideosView(env: env)
        case .words: WordsView(env: env)
        case .review: ReviewView(env: env)
        }
    }
}
