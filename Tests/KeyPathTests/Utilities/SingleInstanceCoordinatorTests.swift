@testable import KeyPathAppKit
import Testing

@Suite("SingleInstanceCoordinator")
struct SingleInstanceCoordinatorTests {
    @Test("Selects the oldest live instance with the same bundle identifier")
    func selectsOldestLiveMatchingInstance() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 88, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
                .init(pid: 17, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
                .init(pid: 12, bundleIdentifier: "com.other.App", isTerminated: false),
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
            ]
        )
        #expect(pid == 17)
    }

    @Test("Ignores terminated instances and returns nil when no live match exists")
    func ignoresTerminatedInstances() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 12, bundleIdentifier: "com.keypath.KeyPath", isTerminated: true),
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
            ]
        )
        #expect(pid == nil)
    }

    @Test("Returns nil for empty candidates list")
    func emptyCandidates() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: []
        )
        #expect(pid == nil)
    }

    @Test("Returns nil when only current process matches")
    func selfOnlyCandidate() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
            ]
        )
        #expect(pid == nil)
    }

    @Test("Returns nil when no bundle identifier matches")
    func noMatchingBundleId() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 10, bundleIdentifier: "com.other.App", isTerminated: false),
                .init(pid: 20, bundleIdentifier: "com.another.App", isTerminated: false),
            ]
        )
        #expect(pid == nil)
    }

    @Test("Ignores candidates with nil bundle identifier")
    func nilBundleIdentifier() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 10, bundleIdentifier: nil, isTerminated: false),
                .init(pid: 20, bundleIdentifier: nil, isTerminated: false),
            ]
        )
        #expect(pid == nil)
    }

    @Test("Returns single live match when only one exists")
    func singleLiveMatch() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 99, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
            ]
        )
        #expect(pid == 99)
    }

    @Test("Skips terminated even when they have lower PID")
    func terminatedLowerPidSkipped() {
        let pid = SingleInstanceCoordinator.existingInstancePID(
            currentPID: 42,
            bundleIdentifier: "com.keypath.KeyPath",
            candidates: [
                .init(pid: 5, bundleIdentifier: "com.keypath.KeyPath", isTerminated: true),
                .init(pid: 100, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false),
            ]
        )
        #expect(pid == 100)
    }
}
