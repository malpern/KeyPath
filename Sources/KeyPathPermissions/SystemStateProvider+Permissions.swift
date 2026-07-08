import KeyPathCore

public extension SystemStateProvider {
    /// Cached/current permission snapshot for installer and wizard decisions.
    ///
    /// Delegates to `PermissionOracle` while Phase 1 grows the full immutable
    /// system snapshot, keeping OS permission reads behind `SystemStateProvider`.
    func currentPermissionSnapshot() async -> PermissionOracle.Snapshot {
        await PermissionOracle.shared.currentSnapshot()
    }

    /// Fresh permission snapshot after a permission prompt or related mutation.
    func refreshPermissionSnapshot() async -> PermissionOracle.Snapshot {
        await PermissionOracle.shared.forceRefresh()
    }

    /// Synchronous KeyPath Accessibility status for hot paths that cannot await.
    ///
    /// Kept behind `SystemStateProvider` so even sync permission probes have one
    /// owner while Phase 1 grows the immutable system snapshot.
    nonisolated func keyPathAccessibilityStatus() -> PermissionOracle.Status {
        PermissionOracle.shared.keyPathAccessibilityStatus()
    }
}
