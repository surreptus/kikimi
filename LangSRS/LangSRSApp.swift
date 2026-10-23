import SwiftUI

@main
struct LangSRSApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("Reprise") {
            RootView()
                .environment(app)
                .task { await app.start() }
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 800)
    }
}
