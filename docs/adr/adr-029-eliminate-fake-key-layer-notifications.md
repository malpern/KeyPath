# ADR-029: Eliminate Fake Key Layer Notifications via Native Kanata LayerChange

**Status:** Proposed
**Date:** 2026-02-06
**Priority:** High

## Context

KeyPath uses `layer-while-held` for momentary layer activation (hold spacebar to enter nav layer, release to return to base). However, Kanata's TCP server does **not** emit `LayerChange` broadcasts for `layer-while-held` transitions -- only for `layer-switch` and `layer-toggle`.

To work around this, KeyPath generates `deffakekeys` entries that fire `push-msg "layer:{name}"` on press and `push-msg "layer:base"` on release. This creates a parallel notification path alongside Kanata's native `LayerChange` broadcasts, requiring complex reconciliation logic in the UI layer.

### The Problem

The dual notification path (push-msg vs native LayerChange) has caused:

1. **Layer state desynchronization** (MAL-61 bug): One-shot-press layers fire an enter fake key but no exit fake key. The `OneShotLayerOverrideState` mechanism blocked the native Kanata `LayerChange -> base` broadcast, leaving the UI stuck on the wrong layer.

2. **Architectural complexity**: Three independent layer state holders (`RuleCollectionsManager`, `RuntimeCoordinator`, `KeyboardVisualizationViewModel`) must reconcile two event sources with different timing characteristics.

3. **500ms polling as safety net**: A `RequestCurrentLayerName` poll runs every 500ms to catch missed events, adding latency and unnecessary TCP traffic.

4. **Config bloat**: Every non-base layer requires two `deffakekeys` entries and `on-press-fakekey`/`on-release-fakekey` wiring in every alias.

### Current Fake Key Usage

| Activation Mode | Enter Notification | Exit Notification | Gap |
|---|---|---|---|
| Standard hold (base -> layer) | Fake key (immediate) | Fake key (immediate) | None |
| One-shot press (base -> nav) | Fake key (immediate) | **None** -- relies on poll | 0-500ms latency |
| Chained one-shot (nav -> window) | Fake key (immediate) | **None** -- relies on poll | 0-500ms latency |
| Hyper hold | Fake key (immediate) | Fake key (immediate) | None |
| Hyper one-shot | Fake key (immediate) | **None** -- relies on poll | 0-500ms latency |
| Mapped key in one-shot | N/A | Direct push-msg (immediate) | None |
| Esc cancel in one-shot | N/A | Direct push-msg (immediate) | None |

**Important**: `push-msg` for application actions (`launch:`, `open:`, `system:`, `window:`, `icon:`, `emphasis:`) is a separate concern that uses `push-msg` correctly and permanently. Only layer state notifications are candidates for elimination.

## Decision

### Phase 1: Upstream Kanata Change (High Priority)

Make `layer-while-held` emit native `LayerChange` TCP broadcasts:
- On activation: `{"LayerChange":{"new":"nav"}}`
- On deactivation (key release): `{"LayerChange":{"new":"base"}}`

Extend to `one-shot-press` layer deactivation if feasible.

This is a change to Kanata's core layer management in `check_handle_layer_change()` or keyberon's layout layer tracking. File as upstream PR against `jtroo/kanata` or implement in the KeyPath fork.

### Phase 2: Simplify KeyPath (After Phase 1)

1. **Config generation**: Remove `renderFakeKeysBlock()`, remove `on-press-fakekey`/`on-release-fakekey` from all alias definitions, remove `push-msg "layer:base"` from `wrapWithOneShotExit` (keep `release-layer`)
2. **Coordination**: Delete `OneShotLayerOverrideState`, remove `source` parameter from `.kanataLayerChanged`, collapse `handleLayerChange` to just `updateLayerName`
3. **Polling**: Reduce `RequestCurrentLayerName` from 500ms to 5s health check only
4. **State consolidation**: Unify the three layer state holders into a single reactive source

## Consequences

### Positive

- Eliminates the entire class of push-vs-kanata reconciliation bugs
- Removes ~200 lines of coordination complexity (one-shot override, dual path handling)
- Reduces generated config size (no fake key definitions)
- Eliminates 500ms polling latency for one-shot layer exits
- Single notification path simplifies reasoning about layer state

### Negative

- Requires upstream Kanata change (may not be accepted by `jtroo/kanata`)
- If carried in fork only, increases fork maintenance burden
- Transition period where both paths must be supported (capability-gated)

## Related

- [ADR-023](adr-023-no-config-parsing.md): No Config Parsing -- uses TCP for layer info
- [ADR-013](adr-013-tcp-without-auth.md): TCP Communication Without Authentication
- [docs/kanata-fork/tcp-overlay-events.md](../kanata-fork/tcp-overlay-events.md): TCP event inventory
- [docs/architecture/layer-coordination-roadmap.md](../architecture/layer-coordination-roadmap.md): Detailed phased roadmap
