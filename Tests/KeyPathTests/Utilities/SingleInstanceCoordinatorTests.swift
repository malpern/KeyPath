@testable import KeyPathAppKit
import Testing

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
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false)
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
                .init(pid: 42, bundleIdentifier: "com.keypath.KeyPath", isTerminated: false)
            ]
        )

        #expect(pid == nil)
    }
}
