@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore

@MainActor
final class StubSystemValidator: WizardSystemValidating {
    private let snapshots: [SystemSnapshot]
    private var nextSnapshotIndex = 0
    private(set) var freshnessRequests: [WizardSystemSnapshotFreshness] = []
    private(set) var cacheInvalidationCount = 0

    init(snapshot: SystemSnapshot) {
        snapshots = [snapshot]
    }

    init(context: SystemContext) {
        snapshots = [Self.snapshot(from: context)]
    }

    init(contexts: [SystemContext]) {
        precondition(!contexts.isEmpty)
        snapshots = contexts.map(Self.snapshot(from:))
    }

    init(snapshots: [SystemSnapshot]) {
        precondition(!snapshots.isEmpty)
        self.snapshots = snapshots
    }

    func checkSystem() async -> SystemSnapshot {
        nextSnapshot()
    }

    func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        freshnessRequests.append(freshness)
        return nextSnapshot()
    }

    func invalidateCaches() {
        cacheInvalidationCount += 1
    }

    private func nextSnapshot() -> SystemSnapshot {
        let snapshot = snapshots[nextSnapshotIndex]
        if nextSnapshotIndex < snapshots.count - 1 {
            nextSnapshotIndex += 1
        }
        return snapshot
    }

    private static func snapshot(from context: SystemContext) -> SystemSnapshot {
        SystemSnapshot(
            id: context.snapshotID,
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            helper: context.helper,
            compatibility: SystemCompatibilityStatus(
                macOSVersion: context.system.macOSVersion,
                driverCompatible: context.system.driverCompatible
            ),
            timestamp: context.timestamp
        )
    }
}
