# Leader Key `selectedOutput` Ignored on Headless Loads (#889)

**Date:** 2026-07-02
**Severity:** Correctness (stale generated config) + a regression caught in review
**Status:** Partial fix in place (in-process load paths); CLI generation path deferred to #865/#888

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

## Known limitations / follow-ups

- **Standalone `keypath-cli config apply` is not covered.** It generates config via
  `ConfigFacade` → `ConfigurationService`, reading `leaderKeyPreference` directly
  and never constructing a `RuleCollectionsManager`, so the reconcile does not run.
  Making config generation derive the leader key from the collection (single source
  of truth) is deferred to #865/#888.
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
