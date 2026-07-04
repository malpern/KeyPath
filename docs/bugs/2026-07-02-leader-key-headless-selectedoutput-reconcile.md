# Leader Key `selectedOutput` Ignored on Headless Loads (#889)

**Date:** 2026-07-02
**Severity:** Correctness (stale generated config) + a regression caught in review
**Status:** In-process load paths fixed (#926/#938); standalone CLI apply path now fixed too (this change). Full single-source-of-truth generation from the collection remains deferred to #865/#888.

## Problem

The Leader Key collection's `selectedOutput` only drove the generated config when
changed through the in-app picker, which routes through
`RuleCollectionsManager.updateLeaderKey` and syncs the system
`leaderKeyPreference` (UserDefaults). Config generation derives the primary
leader binding from `leaderKeyPreference`, **independent of the collection**
(see `KanataConfiguration+BlockBuilders.swift`).

Headless mutations — direct `RuleCollections.json` edits and import/restore —
change `selectedOutput` without touching `leaderKeyPreference`, so generation
silently kept the old leader key.

## Fix (proximate)

`RuleCollectionsManager.reconcileLeaderKeyFromCollection()`, invoked from the two
in-process load paths (`bootstrap()` and `replaceCollections()`), syncs
`leaderKeyPreference` from the enabled Leader Key collection's **explicit**
`selectedOutput` before config regeneration. A nil `selectedOutput` is treated as
"no opinion" and does not clobber a leader configured via the system-preference
path.

## Regression caught during review (the deeper lesson)

The first implementation reused the existing `applyLeaderKeyToMomentaryActivators`,
which rewrites the `input` of **every** collection's `momentaryActivator` to the
new leader key. That is acceptable-ish for an explicit UI "change my leader key"
action, but wiring it into every headless load meant it would stomp unrelated,
default-enabled features whenever the preference diverged:

- **Home Row Arrows** (`base → home-arrows`, input `f`)
- **Quick Launcher** (`base → launcher`, input `hyper`) — collapsing `hyper` onto
  the leader key also defeats the Hyper special-casing in config generation and
  collides two base-layer bindings on the same key.

Fix: `applyLeaderKeyToLeaderActivators(_:targetLayer:)` rewrites only the
`base → <leader target layer>` (i.e. base → nav) activators, leaving unrelated
base-layer and chained `nav → *` sub-layer activators untouched. Regression guard
added in `testReplaceCollectionsReconcilesLeaderKeyFromSelectedOutput`.

## Rollback coverage (test gap closed post-merge)

The atomic rollback (`rollbackLeaderReconcile`) could not be unit-tested on the
toolchain-less Linux remote where this shipped — regen only fails on a genuine
collision, which needs a real macOS build. `testReconcileRollsBackWhenConfigRegenFails`
now closes that gap: it reconciles the leader to `f` (colliding with the enabled
Home Row Arrows `base → home-arrows` activator), which makes
`generateConfiguration` throw `.mappingConflicts` (#463) with no
`onMappingConflictResolution` handler registered, then asserts that **both** the
`leaderKeyPreference` and the in-memory `ruleCollections` revert to their
pre-reconcile snapshot. An `onError` spy witnesses the regen failure so the test
can't silently pass on a no-op reconcile.

## CLI apply path closed (this change)

The remaining headless gap — the standalone `keypath-cli config apply` — is now
covered. `ConfigFacade.applyConfiguration` reconciles the leader key from the
loaded Leader Key collection's explicit `selectedOutput` before generating config:

- The reconcile rule was extracted into a **pure, shared** function,
  `LeaderKeyPreference.reconciled(from:current:)`, now used by BOTH the in-process
  `RuleCollectionsManager.reconcileLeaderKeyFromCollection` and the CLI path — one
  statement of the rule, so all headless paths agree.
- Config generation emits a `;; Input:` binding annotation *per collection activator*,
  not just from `leaderKeyPreference`. So the CLI must also rewrite the Leader Key
  collection's base→nav activator, or the generated config keeps the stale binding.
  A second pure helper, `LeaderKeyPreference.reconcileLeaderActivators(in:key:targetLayer:)`,
  does that scoped rewrite (base→leader-target only, leaving Home Row Arrows "f" /
  Quick Launcher "hyper" untouched) and is shared with the manager's
  `applyLeaderKeyToLeaderActivators`.
- **Dry run** reconciles for the preview but restores the pre-reconcile
  `leaderKeyPreference` afterward (including on a generation/validation throw), so
  `keypath apply --dry-run` never mutates persisted state.
- `Scripts/qa-leader-key-smoke.sh` assertions were flipped: each preset now must drive
  its own `;; Input: <key>` binding through the CLI, not just apply cleanly.

## Known limitations / follow-ups

- **Disable-drift is not reconciled.** A headless edit that *disables* a
  previously-reconciled collection leaves `leaderKeyPreference` stale; forcing it
  disabled would clobber a system-preference leader. Deferred to #865/#888.
- **`targetLayer` coupling.** The scoped activator update derives the leader target
  layer from `leaderKeyPreference.targetLayer` (always `.navigation` today). If a
  future non-navigation leader layer is introduced, this filter would match zero
  activators; revisit alongside the #865/#888 single-source-of-truth work.

## Also in the same change (#850)

Four `try! NSRegularExpression` static lets in `LayerMappingBuilder` were converted
to `try?` with guarded call sites, removing a latent force-unwrap crash path
(audit §5.3 regression).
