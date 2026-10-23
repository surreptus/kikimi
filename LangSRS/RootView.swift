import LangCore
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showAcknowledgements = false
    @State private var showStorage = false
    /// +1 when moving down the nav list, -1 when moving up; decides which way the new screen slides in.
    @State private var direction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Opening your library…").font(Theme.title(18)).foregroundStyle(Theme.pinkText)
                }
            case .failed(let message):
                ContentUnavailableView("Couldn't start", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready(let env):
                layout(env)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .containerBackground(Theme.background, for: .window)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(Theme.pink)
        .fontDesign(.rounded)
        .sheet(isPresented: $showAcknowledgements) { AcknowledgementsView() }
    }

    /// A floating nav card on the left, and the current screen in its own rounded card.
    private func layout(_ env: LangEnvironment) -> some View {
        @Bindable var app = app
        let selection = Binding<SidebarItem>(
            get: { app.section },
            set: { new in
                direction = new.order >= app.section.order ? 1 : -1
                withAnimation(Theme.screenChange(reduceMotion)) { app.section = new }
            })
        return HStack(spacing: 14) {
            FloatingNav(
                selection: selection, dueCount: app.dueCount,
                languages: LanguageProfiles.all.map { ($0.code, $0.displayName) },
                language: $app.languageCode, showStorage: { showStorage = true },
                showAcknowledgements: { showAcknowledgements = true })
            ZStack {
                detail(env: env)
                    .id(app.section)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .modifier(active: ScreenShift(y: direction * 26, opacity: 0),
                                             identity: ScreenShift(y: 0, opacity: 1)),
                        removal: .opacity))
            }
            .animation(Theme.screenChange(reduceMotion), value: app.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 28).fill(Theme.card))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.line, lineWidth: 2))
        }
        .padding(14)
        .sheet(isPresented: $showStorage) { StorageView(env: env) }
    }

    @ViewBuilder
    private func detail(env: LangEnvironment) -> some View {
        switch app.section {
        case .importVideos: ImportView(env: env)
        case .review: ReviewView(env: env)
        case .words: WordsView(env: env)
        case .library: LibraryView(env: env)
        }
    }
}
