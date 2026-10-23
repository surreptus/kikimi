import SwiftUI

@main
struct LangSRSApp: App {
    @State private var app = AppState()
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some Scene {
        // One window: there is one library, so a second window would only show the same thing.
        Window("Reprise", id: "main") {
            RootView()
                .environment(app)
                .task { await app.start() }
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 1240, height: 800)
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView().environment(app)
        }
    }
}
