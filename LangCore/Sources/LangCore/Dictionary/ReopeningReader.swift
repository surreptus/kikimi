import Foundation
import GRDB

/// A built, read-only database file (a dictionary) held open for the life of the app, which opens it again, once, when SQLite says
/// the disk failed under it. That is what happens to an open connection when the file is replaced under it: a rebuilt app, or
/// one copied over the old while it was running, swaps the bundled file for a new one. Opening it again reads the new file, so
/// a lookup that would have failed with "disk I/O error" gives its answer.
final class ReopeningReader: Sendable {
    private let url: URL
    private let state: Mutex

    /// The open connection, behind a lock; everything else is immutable.
    private final class Mutex: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: DatabaseQueue
        init(_ queue: DatabaseQueue) { self.queue = queue }
        var current: DatabaseQueue { lock.withLock { queue } }
        /// Replaces `old` with a fresh connection, unless another caller already has.
        func replace(_ old: DatabaseQueue, using open: () throws -> DatabaseQueue) throws -> DatabaseQueue {
            try lock.withLock {
                if queue === old { queue = try open() }
                return queue
            }
        }
    }

    init(url: URL) throws {
        self.url = url
        state = Mutex(try Self.open(url))
    }

    private static func open(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    /// For reading the file's shape when it is first opened.
    func readNow<T>(_ body: (Database) throws -> T) throws -> T { try state.current.read(body) }

    func read<T: Sendable>(_ body: @Sendable @escaping (Database) throws -> T) async throws -> T {
        let queue = state.current
        do {
            return try await queue.read(body)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_IOERR {
            let url = self.url
            let fresh = try state.replace(queue) { try Self.open(url) }
            return try await fresh.read(body)
        }
    }
}
