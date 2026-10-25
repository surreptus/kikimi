import Foundation

/// Calls `release` once nothing has used a resource for `delay`. Each `begin` cancels the wait, so a long job is never
/// cut off, and the wait restarts when the last user is done. Used to give the speech model's memory back.
actor IdleRelease {
    private let delay: Duration
    private let release: @Sendable () async -> Void
    private var active = 0
    private var timer: Task<Void, Never>?

    init(after delay: Duration, release: @escaping @Sendable () async -> Void) {
        self.delay = delay
        self.release = release
    }

    func begin() {
        active += 1
        timer?.cancel()
        timer = nil
    }

    func end() {
        active = max(0, active - 1)
        guard active == 0 else { return }
        timer?.cancel()
        let delay = delay, release = release
        timer = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await release()
        }
    }

    /// Runs `body` as a use of the resource.
    func use<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        begin()
        do {
            let result = try await body()
            end()
            return result
        } catch {
            end()
            throw error
        }
    }
}
