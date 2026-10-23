import SwiftUI

@main
struct LangSRSApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.start() }
                .frame(minWidth: 820, minHeight: 540)
        }
    }
}
