#if DEBUG
import Foundation

/// A developer aid, in Debug builds only: puts the library aside so the app starts empty. Nothing is deleted. The database,
/// the videos and the staging folder move into "Set Aside/<date and time>" beside them, where they can be moved back; the
/// speech models, which are large and slow to download, stay where they are.
public enum LibraryReset {
    static let items = ["kikimi.sqlite", "kikimi.sqlite-wal", "kikimi.sqlite-shm", "kikimi.sqlite-journal", "Library", "Staging"]

    /// Moves what is there into a new folder and returns it, or returns nil when there was nothing to move.
    @discardableResult
    public static func setAside(root: URL, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        let present = items.filter { fm.fileExists(atPath: root.appending(path: $0).path) }
        guard !present.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let folder = root.appending(path: "Set Aside", directoryHint: .isDirectory)
            .appending(path: formatter.string(from: now), directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in present { try fm.moveItem(at: root.appending(path: name), to: folder.appending(path: name)) }
        return folder
    }
}
#endif
