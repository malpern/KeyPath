import KeyPathCore

public extension SystemStateProvider {
    /// Passive capabilities of the calling process, sampled by the session worker.
    func currentProcessSessionCapabilities() async -> PermissionOracle.ProcessCapabilities {
        await PermissionOracle.shared.currentProcessSessionCapabilities()
    }

    /// A single passive sample with raw facts kept distinct from readiness policy.
    func currentProcessSessionCapabilitySnapshot() async -> PermissionOracle.SessionCapabilitySnapshot {
        await PermissionOracle.shared.currentProcessSessionCapabilitySnapshot()
    }

    /// Bind the session runtime's report through the canonical permission snapshot owner.
    func configureRuntimeKeyAccessProvider(
        _ provider: @escaping @Sendable () async -> PermissionOracle.RuntimeKeyAccess?
    ) async {
        await PermissionOracle.shared.configureRuntimeKeyAccessProvider(provider)
    }

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

    /// Discard permission evidence gathered before a runtime change, including
    /// an in-flight sample, so the next decision reads the current runtime.
    func invalidatePermissionSnapshot() async {
        await PermissionOracle.shared.invalidateCache()
    }

    /// Synchronous KeyPath Accessibility status for hot paths that cannot await.
    ///
    /// Kept behind `SystemStateProvider` so even sync permission probes have one
    /// owner while Phase 1 grows the immutable system snapshot.
    nonisolated func keyPathAccessibilityStatus() -> PermissionOracle.Status {
        PermissionOracle.shared.keyPathAccessibilityStatus()
    }

    /// Whether a listen-only event tap is already permitted, without prompting.
    nonisolated func keyPathCanCreateListenOnlyTap() -> Bool {
        PermissionOracle.shared.keyPathCanCreateListenOnlyTap()
    }
}
