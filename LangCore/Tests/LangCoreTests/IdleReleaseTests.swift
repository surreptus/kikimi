import XCTest
@testable import LangCore

final class IdleReleaseTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func testReleasesOnceAfterTheLastUseHasBeenIdleForTheDelay() async throws {
        let released = Counter()
        let idle = IdleRelease(after: .milliseconds(80)) { released.bump() }
        try await idle.use { }
        XCTAssertEqual(released.value, 0, "not straight away")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(released.value, 1)
    }

    func testAJobThatRunsLongerThanTheDelayIsNeverCutOff() async throws {
        let released = Counter()
        let idle = IdleRelease(after: .milliseconds(50)) { released.bump() }
        try await idle.use { try await Task.sleep(for: .milliseconds(300)); XCTAssertEqual(released.value, 0) }
        XCTAssertEqual(released.value, 0)
    }

    func testANewUseRestartsTheWait() async throws {
        let released = Counter()
        let idle = IdleRelease(after: .milliseconds(150)) { released.bump() }
        try await idle.use { }
        try await Task.sleep(for: .milliseconds(80))
        try await idle.use { }          // before the first wait ran out
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(released.value, 0, "the wait started again from the second use")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(released.value, 1)
    }

    func testAFailedUseStillCountsAsFinished() async throws {
        let released = Counter()
        let idle = IdleRelease(after: .milliseconds(60)) { released.bump() }
        do { try await idle.use { throw Failure() } } catch {}
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(released.value, 1)
    }
}
