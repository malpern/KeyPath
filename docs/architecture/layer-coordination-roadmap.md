# Layer State Coordination: Architecture Roadmap

**Date:** 2026-02-06
**Status:** Proposed
**Related ADR:** [ADR-029](../adr/adr-029-eliminate-fake-key-layer-notifications.md)

## Problem Statement

KeyPath's keyboard overlay needs to know which Kanata layer is active. Kanata's `layer-while-held` (used for momentary layers) does not emit `LayerChange` TCP broadcasts. KeyPath works around this with fake keys that fire `push-msg` events, creating a dual notification architecture with complex reconciliation logic.

## Current Architecture

### Two Notification Paths

```
Path A (Native):  Kanata LayerChange broadcast
                  → KanataEventListener
                  → RuleCollectionsManager.updateActiveLayerName()
                  → .kanataLayerChanged (source: "kanata")
                  → LiveKeyboardOverlayController.handleLayerChange()
                  → viewModel.updateLayer()

Path B (Fake Key): Kanata push-msg "layer:X"
                   → KanataEventListener → ActionDispatcher
                   → App.onLayerAction
                   → LiveKeyboardOverlayController.updateLayerName() [direct]
                   → .kanataLayerChanged (source: "push")
                   → LiveKeyboardOverlayController.handleLayerChange() [again]
                   → viewModel.updateLayer()
```

### Reconciliation via OneShotLayerOverrideState

Push messages (Path B) take priority over native broadcasts (Path A) to avoid flicker from the 500ms poll. The `OneShotLayerOverrideState` class blocks kanata-source updates while a push-source layer is active. This was the source of the MAL-61 stuck-layer bug: one-shot layers fire an enter push but no exit push, so the override blocked the native "base" broadcast.

### Three Independent Layer State Holders

1. `RuleCollectionsManager.currentLayerName` -- updated by Path A
2. `RuntimeCoordinator.currentLayerName` -- copied from RuleCollectionsManager callback
3. `KeyboardVisualizationViewModel.currentLayerName` -- updated by both paths

These can transiently diverge during the reconciliation window.

### 500ms Polling Safety Net

`KanataEventListener` sends `RequestCurrentLayerName` every 500ms. This catches missed events and provides the exit signal for one-shot layers that lack an exit fake key.

## Fake Key Inventory

### Category A: Layer State Notifications (replaceable)

| Pattern | Generated In | Could Native TCP Replace? |
|---|---|---|
| `kp-layer-{name}-enter` (push-msg "layer:{name}") | `renderFakeKeysBlock()` | YES |
| `kp-layer-{name}-exit` (push-msg "layer:base") | `renderFakeKeysBlock()` | YES |
| `on-press-fakekey kp-layer-{name}-enter tap` | BlockBuilders, BehaviorRenderer | YES |
| `on-release-fakekey kp-layer-{name}-exit tap` | BlockBuilders, BehaviorRenderer | YES |
| Direct `(push-msg "layer:base")` in wrapWithOneShotExit | BlockBuilders | YES |
| Direct `(push-msg "layer:base")` in Esc cancel | BlockBuilders | YES |

### Category B: Application Actions (permanent, correct use of push-msg)

| Pattern | Purpose |
|---|---|
| `launch:{appId}` | Launch macOS application |
| `open:{url}` | Open URL in browser |
| `folder:{path}` | Open folder in Finder |
| `script:{path}` | Execute script |
| `system:{action}` | Mission Control, Spotlight, DND, etc. |
| `window:{action}` | Window snapping and management |

### Category C: UI Hints (permanent, correct use of push-msg)

| Pattern | Purpose |
|---|---|
| `icon:{name}` | Custom key icon on overlay |
| `emphasis:{keys}` | Highlight specific keys |

## Phased Roadmap

### Phase 1: Native `LayerChange` for `layer-while-held` (Kanata Upstream)

**Effort:** Medium-High | **Reward:** Transformative | **Priority:** High

Make `layer-while-held` emit `LayerChange` on activation and deactivation. This is a change to Kanata's `check_handle_layer_change()` or keyberon's layer tracking.

**Approach options:**
1. **Upstream PR to `jtroo/kanata`**: Best long-term, but may be controversial. Discuss in issue first.
2. **Fork-only**: Increases maintenance burden but unblocks immediately.

**Also needed:** `one-shot-press` should emit `LayerChange` when the one-shot is consumed (layer deactivates). This may require changes in keyberon's one-shot state machine.

**Deliverables:**
- Kanata emits `{"LayerChange":{"new":"nav"}}` when `layer-while-held nav` activates
- Kanata emits `{"LayerChange":{"new":"base"}}` when the hold key is released
- Kanata emits `{"LayerChange":{"new":"base"}}` when `one-shot-press` layer is consumed
- Capability flag: `"layer_while_held_change"` in HelloOk

### Phase 2: Simplify KeyPath Coordination (After Phase 1)

**Effort:** Medium | **Reward:** High | **Priority:** High (after Phase 1)

#### 2a. Remove Fake Key Config Generation

- Delete `renderFakeKeysBlock()` from `KanataConfiguration+Rendering.swift`
- Remove `on-press-fakekey` / `on-release-fakekey` from all alias definitions in `BlockBuilders.swift` and `BehaviorRenderer.swift`
- Remove `push-msg "layer:base"` from `wrapWithOneShotExit` (keep `release-layer`)
- Remove `push-msg "layer:base"` from Esc cancel output (keep `release-layer` + `XX`)
- Gate behind capability: only remove if server advertises `layer_while_held_change`

#### 2b. Remove One-Shot Override Mechanism

- Delete `OneShotLayerOverrideState` class from `LiveKeyboardOverlayTypes.swift`
- Remove all one-shot override logic from `LiveKeyboardOverlayController.handleLayerChange()`
- Remove all one-shot override logic from `ContextHUDController.handleLayerChange()`
- Remove `source` parameter from `.kanataLayerChanged` notification
- Collapse `handleLayerChange` to just `updateLayerName`

#### 2c. Reduce Polling

- Change `RequestCurrentLayerName` interval from 500ms to 5000ms (health check only)
- Or replace with a simple TCP keepalive ping

### Phase 3: Consolidate Layer State (After Phase 2)

**Effort:** Low-Medium | **Reward:** Moderate | **Priority:** Normal

- Unify `RuleCollectionsManager.currentLayerName`, `RuntimeCoordinator.currentLayerName`, and `viewModel.currentLayerName` into a single reactive source
- Remove the redundant direct `updateLayerName` call in `App.swift:647` (line 647's direct call + the notification path is a double-write)
- Remove `ActionDispatcher.onLayerAction` -- no longer needed once fake key `layer:` messages are gone

### Phase 4: Overlay Event Richness (Independent, Ongoing)

**Effort:** Medium per event | **Reward:** Moderate | **Priority:** Normal

Continue keyberon work for emission points (independent of fake key elimination):

| Event | Keyberon Location | Purpose |
|---|---|---|
| `OneShotActivated` | One-shot state machine | Show "modifier pending" indicator |
| `ChordResolved` | Chord recognition logic | Show resolved chord output |
| `TapDanceResolved` | Tap-dance timeout handler | Show resolved tap-dance action |
| Action string in `HoldActivated`/`TapActivated` | `waiting_into_hold()`/`waiting_into_tap()` | Eliminate simulator-based label fallback |

## What Does NOT Change

- `push-msg` for application actions (Category B) is permanent and correct
- `push-msg` for UI hints (Category C) is permanent and correct
- `KeyPathActionURI` parsing and `ActionDispatcher` routing stay as-is
- The `KeyInput`/`HoldActivated`/`TapActivated` TCP events (from the recent Kanata PR) are orthogonal and stay

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Upstream PR rejected | Carry in fork; already diverge for KeyInput/HoldActivated |
| Capability negotiation complexity | Gate behind `layer_while_held_change` capability in HelloOk |
| Regression during transition | Keep fake key path as fallback when capability not advertised |
| Kanata version fragmentation | Graceful degradation: if capability missing, use legacy fake key path |
