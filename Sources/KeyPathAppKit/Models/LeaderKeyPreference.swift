import Foundation
import KeyPathRulesCore

/// System-level preference for the primary leader key
/// This defines which key activates the navigation/leader layer
/// Independent of any collection - collections just declare they target this layer
public struct LeaderKeyPreference: Codable, Equatable, Sendable {
    /// The physical key that activates the leader layer
    public var key: String

    /// The layer that gets activated
    public var targetLayer: RuleCollectionLayer

    /// Whether leader key is enabled at all
    public var enabled: Bool

    /// Default configuration: Space → Nav layer, enabled
    public static let `default` = LeaderKeyPreference(
        key: "space",
        targetLayer: .navigation,
        enabled: true
    )

    public init(key: String, targetLayer: RuleCollectionLayer, enabled: Bool) {
        self.key = key
        self.targetLayer = targetLayer
        self.enabled = enabled
    }
}

public extension LeaderKeyPreference {
    /// Derive the leader-key preference implied by the enabled Leader Key collection's
    /// explicit `selectedOutput`, or `nil` if the collection expresses no opinion.
    ///
    /// This is the single, pure statement of the reconcile rule that keeps the collection
    /// (`selectedOutput`) and the system `leaderKeyPreference` in agreement. It is shared by:
    ///
    /// - the in-process load paths (`RuleCollectionsManager.bootstrap`/`replaceCollections`),
    ///   which mutate `PreferencesService` and the base→nav activators, and
    /// - the standalone CLI apply path (`ConfigFacade.applyConfiguration`), which reads
    ///   `leaderKeyPreference` directly when generating config and never constructs a
    ///   `RuleCollectionsManager`. Without this, `keypath collection` mutations / direct
    ///   `RuleCollections.json` edits to `selectedOutput` were silently ignored by
    ///   `keypath apply` (issue #889).
    ///
    /// Guardrails (mirroring `RuleCollectionsManager.reconcileLeaderKeyFromCollection`):
    /// - Only an *explicit* `selectedOutput` reconciles. A `nil` `selectedOutput` means the
    ///   collection has no opinion, so a leader configured via the system-preference path is
    ///   left untouched (no fallback to the first preset).
    /// - A disabled collection does not reconcile — forcing it disabled here would clobber a
    ///   leader configured via the system-preference path while the collection is off. Full
    ///   bidirectional (disable-drift) reconciliation is deferred to #865/#888.
    ///
    /// - Returns: the reconciled preference (key set from `selectedOutput`, `enabled = true`),
    ///   or `nil` when there is nothing to change (no collection, disabled, no explicit output,
    ///   or the preference already matches).
    static func reconciled(
        from collections: [RuleCollection],
        current: LeaderKeyPreference
    ) -> LeaderKeyPreference? {
        guard let leaderCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.leaderKey }),
              leaderCollection.isEnabled,
              let key = leaderCollection.configuration.singleKeyPickerConfig?.selectedOutput
        else { return nil }

        guard current.key != key || !current.enabled else { return nil }

        var reconciled = current
        reconciled.key = key
        reconciled.enabled = true
        return reconciled
    }

    /// Rewrite the input of only the *leader* activators in `collections` — those transitioning
    /// from the base layer into the leader's `targetLayer` (e.g. base → nav) — to `key`.
    ///
    /// This deliberately leaves unrelated base-layer activators alone (e.g. Home Row Arrows on
    /// "f", Quick Launcher on "hyper") and chained sub-layer activators (`sourceLayer != .base`),
    /// which have their own activation keys. It mirrors
    /// `RuleCollectionsManager.applyLeaderKeyToLeaderActivators` so the CLI apply path produces a
    /// config identical to the in-process reconcile. Rewriting the leader activator (not just the
    /// system preference) matters because config rendering emits a `;; Input:` binding annotation
    /// per collection activator; leaving the Leader Key collection's activator on the stale key
    /// would keep the old binding in the generated config. See issue #889.
    static func reconcileLeaderActivators(
        in collections: [RuleCollection],
        key: String,
        targetLayer: RuleCollectionLayer
    ) -> [RuleCollection] {
        collections.map { collection in
            guard let activator = collection.momentaryActivator,
                  activator.sourceLayer == .base,
                  activator.targetLayer == targetLayer
            else { return collection }
            var updated = collection
            updated.momentaryActivator = MomentaryActivator(
                input: key,
                targetLayer: activator.targetLayer,
                sourceLayer: activator.sourceLayer
            )
            return updated
        }
    }
}
