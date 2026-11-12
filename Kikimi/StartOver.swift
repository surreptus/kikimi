import AppKit
import LangCore

/// Settings > Data > Danger zone: start with an empty library. The database is open while the app runs, so the request is saved,
/// the app quits, and it is carried out at the next launch before anything opens the library. Nothing is deleted: `LibraryReset`
/// moves the database, the videos and the staging folder into a Set Aside folder, and the speech models stay. We never delete a
/// person's data ourselves; we show them where it is and let them.
enum StartOver {
    private static let key = "startOverOnLaunch"

    static func request() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    /// At launch, first of all: carries out a request that was made.
    static func applyPending() {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        if let root = try? LangEnvironment.standardRoot() { _ = try? LibraryReset.setAside(root: root) }
    }

    /// Where earlier ones were put, once there is something there.
    static func setAsideFolder() -> URL? {
        (try? LangEnvironment.standardRoot()).flatMap { LibraryReset.setAsideFolder(root: $0) }
    }
}
