#if DEBUG
import AppKit
import LangCore
import SwiftUI

/// Developer aids, in Debug builds only: start again with an empty library. The database is open while the app runs, so
/// the reset is asked for here, the app quits, and it is carried out at the next launch before anything opens the library.
/// Nothing is deleted (see `LibraryReset`).
enum DebugReset {
    enum Kind: String {
        /// The database and the videos.
        case library
        /// Also the app's settings, so the welcome page and every first-use hint come back.
        case everything

        var message: String {
            switch self {
            case .library:
                String("Your words, progress and videos are moved to a Set Aside folder in Kikimi's Application Support folder; nothing is deleted, and the speech models stay. Kikimi quits. Open it again to start with an empty library.")
            case .everything:
                String("As Reset Library, and the app's settings are cleared too, so the welcome page and the first-use hints come back. Kikimi quits. Open it again to start fresh.")
            }
        }
    }

    private static let key = "debugResetOnLaunch"

    static func request(_ kind: Kind) {
        UserDefaults.standard.set(kind.rawValue, forKey: key)
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    /// At launch, first of all: carries out a reset that was asked for.
    static func applyPending() {
        guard let raw = UserDefaults.standard.string(forKey: key), let kind = Kind(rawValue: raw) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        if let root = try? LangEnvironment.standardRoot() { _ = try? LibraryReset.setAside(root: root) }
        if kind == .everything, let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
    }
}

struct DebugResetAlert: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content.alert(
            "Reset the library?",
            isPresented: Binding(get: { app.confirmingReset != nil }, set: { if !$0 { app.confirmingReset = nil } })
        ) {
            Button("Reset and Quit", role: .destructive) { if let kind = app.confirmingReset { DebugReset.request(kind) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.confirmingReset?.message ?? "")
        }
    }
}
#endif
