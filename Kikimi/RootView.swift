import LangCore
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Opening your library…").font(Theme.title(18)).foregroundStyle(Theme.ink)
                }
            case .failed(let message):
                FailureView(title: "Couldn't start", detail: message)
            case .ready(let env):
                if app.needsOnboarding { OnboardingView(env: env) } else { layout(env).modifier(AnkiExportFlow(env: env)) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { ToastHost() }
        .background { ZStack { windowColor; NoiseOverlay() } }
        .containerBackground(for: .window) { ZStack { windowColor; NoiseOverlay() } }
        .onChange(of: colorScheme, initial: true) { _, scheme in DockIcon.show(for: scheme) }
        .onChange(of: app.settingsRequest) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(Theme.accent)
        .font(Theme.styled(.body, design: .rounded))   // text with no font of its own, at the chosen size (Settings > General)
        .fontDesign(.rounded)
        .modal(isPresented: Binding(get: { app.showAcknowledgements }, set: { app.showAcknowledgements = $0 })) { AcknowledgementsView() }
        #if DEBUG
        .modifier(DebugResetAlert())
        #endif
    }

    /// The window is the sidebar's colour once the library is open, with the page in a card on it; while it opens, or
    /// if it can't, or on the welcome page, there is no card, so the page colour fills the window.
    private var windowColor: Color { app.isReady && !app.needsOnboarding ? Theme.chrome : Theme.field }

    /// The sidebar sits directly on the window; the current page is a rounded card beside it.
    private func layout(_ env: LangEnvironment) -> some View {
        @Bindable var app = app
        let selection = Binding<SidebarItem>(
            get: { app.section },
            set: { app.select($0, reduceMotion: reduceMotion) })
        return HStack(spacing: 0) {
            SideNav(
                selection: selection, dueCount: app.dueCount, lessonsWaiting: app.lessonsWaiting,
                languages: app.learning.map { ($0.code, $0.displayName) },
                language: $app.languageCode, showAbout: { app.showAbout = true },
                showSettings: { app.openSettings(app.settingsTab) })
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
            .card()
        }
        .modal(isPresented: $app.showStorage) { StorageView(env: env) }
        .modal(isPresented: $app.showAbout) { AboutView() }
        .modal(isPresented: $app.showPrivacy) { DocumentView(title: "Privacy policy", resource: "Privacy") }
        .modal(isPresented: $app.showTerms) { DocumentView(title: "Terms of use", resource: "Terms") }
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

private extension View {
    /// The page card: plain, with the window's grain only around it, rounded so a page sliding in stays inside it.
    func card(leading: CGFloat = 0) -> some View {
        self.background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 10).padding(.trailing, 10).padding(.bottom, 10).padding(.leading, leading)
            .ignoresSafeArea(.container, edges: .top)   // the card starts 10 points from the window's top edge
    }
}
