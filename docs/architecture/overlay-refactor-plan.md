# Overlay Rendering Refactor Plan

## Context

The overlay keyboard rendering code has accumulated structural debt that makes bugs hard to prevent and diagnose. During a single session (2026-05-26), three HJKL rendering regressions were introduced and fixed:

1. **Augmentation dropped vimLabels** — arrows showed "H — Left" text instead of "←"
2. **Floating labels bled through vim hints** — HJKL showed letter + arrow overlap in KindaVim mode
3. **Floating labels hidden in wrong mode** — HJKL went blank on base layer when KindaVim pack was installed

Root cause: the overlay has 4+ rendering layers with visibility driven by ~10 interacting state flags, no clear data flow, and no way to test layer composition.

## Current State (2026-05-26)

| Component | LOC | Files | Parameters | Computed Props |
|-----------|-----|-------|------------|----------------|
| OverlayKeycapView | 2,685 | 16 | 60 | 50+ |
| OverlayKeyboardView | 958 | 1 | 24 | 33 |
| LayoutMapping ViewModel | 721 | 1 | N/A | 10+ funcs |
| LiveKeyboardOverlayView | 2,673 | 8 | N/A | 30+ @State |

## Phase 1: FloatingLabelVisibilityModel (Highest Impact)

**Problem:** Floating label visibility is a 7-condition boolean chain in `OverlayKeyboardView.swift`:
```swift
isVisible: labelToKeyCode[label] != nil
    && !isSpecialLabel(label)
    && !isLauncherMode
    && !isLayerMode
    && !isRemappedLabel(label)
    && !hasZoneSubtitle(for: label)
    && !(vimHintsActive && isLoudVimHintLabel(label))
```
One missing condition = regression. Untestable in isolation.

**Fix:** Extract to a testable struct:
```swift
struct FloatingLabelVisibility {
    let labelToKeyCode: [String: UInt16]
    let isLauncherMode: Bool
    let isLayerMode: Bool
    let vimHintsActive: Bool
    let remappedLabels: Set<String>
    let zoneSubtitleLabels: Set<String>

    func isVisible(_ label: String) -> Bool { ... }
}
```

**Files:** `Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift`
**Tests:** Add to `Tests/KeyPathTests/UI/OverlayHJKLRegressionTests.swift`
**Risk:** Low — pure extraction, no behavior change.

## Phase 2: LayerMappingBuilder Pipeline

**Problem:** `KeyboardVisualizationViewModel+LayoutMapping.swift` (721 LOC) does 5+ jobs. The augmentation pipeline is implicit: raw mapping → enrichWithCustomShiftLabels → augmentWithPushMsgActions → final mapping. The `mergeAugmentation` bug (dropping vimLabels) happened because one step silently destroyed data from a previous step.

**Fix:** Create an explicit, ordered pipeline:
```swift
struct LayerMappingBuilder {
    let rawMapping: [UInt16: LayerKeyInfo]
    let customRules: [CustomRule]
    let ruleCollections: [RuleCollection]
    let layerName: String

    func build() -> [UInt16: LayerKeyInfo] {
        var mapping = rawMapping
        mapping = enrichWithCustomShiftLabels(mapping)
        mapping = augmentWithPushMsgActions(mapping)
        mapping = buildRemapOutputMap(mapping)
        return mapping
    }
}
```

Each step is a pure function that takes mapping in, returns mapping out. Steps validate invariants (e.g., vimLabels are never dropped). The builder is testable end-to-end.

**Files:**
- New: `Sources/KeyPathAppKit/Services/LayerMapping/LayerMappingBuilder.swift`
- Refactor: `Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel+LayoutMapping.swift` (calls builder instead of inline augmentation)

**Tests:** Test each pipeline step preserves vimLabels, collectionIds, etc.
**Risk:** Medium — touches the data flow but not the rendering.

## Phase 3: State Grouping in LiveKeyboardOverlayView

**Problem:** 30+ @State variables with no logical grouping. Drag state (4 vars), runtime state (4 vars), inspector state (3 vars), toast state (3 vars) are all independent.

**Fix:** Group into structs:
```swift
struct OverlayDragState {
    var initialFrame: CGRect?
    var initialMouseLocation: CGPoint?
    var isKeyboardDragging: Bool
    var isHeaderDragging: Bool
}

struct OverlayRuntimeState {
    var lastRuntimeIssuePresent: Bool
    var hasSeenHealthyRuntime: Bool
    var showingRuntimeStoppedAlert: Bool
}
```

Replace `@State var isKeyboardDragging` with `@State var dragState = OverlayDragState()`.

**Files:** `Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayView.swift` and extensions
**Risk:** Low — pure state reorganization, no behavior change.

## Phase 4: OverlayKeycapView Decomposition

**Problem:** 60 parameters, 50+ computed properties, 2,685 LOC across 16 files. Every rendering concern flows through one view.

**Fix:** Composition instead of parameters. Break into focused child views:
- `LayerModeKeycap` — handles layer mode rendering (nav, window, etc.)
- `LauncherModeKeycap` — handles launcher mode (app icons, transitions)
- `BaseKeycap` — handles base layer (floating labels, shift labels, hold labels)

The parent `OverlayKeycapView` selects which child to render based on mode, passing only the relevant 10-15 parameters to each.

**Files:** All `OverlayKeycapView+*.swift` extensions
**Risk:** High — touches the core rendering path. Needs comprehensive snapshot tests first.
**Prerequisite:** Snapshot tests (added in PR #586) and Phases 1-2.

## Phase 5: Cache Invalidation Cleanup

**Problem:** Same label cache rebuilt in 3 separate `onChange` blocks in OverlayKeyboardView. Adding a 4th trigger is error-prone.

**Fix:** Single computed cache that auto-invalidates:
```swift
private var labelCacheKey: String {
    "\(keymap.id)|\(includeKeymapPunctuation)|\(layout.id)"
}
```

Or use a single `onChange` on the cache key that rebuilds both caches.

**Files:** `Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift`
**Risk:** Low.

## Execution Order

| Phase | Risk | Effort | Dependency |
|-------|------|--------|------------|
| 1. FloatingLabelVisibilityModel | Low | Small | None |
| 2. LayerMappingBuilder | Medium | Medium | None |
| 3. State Grouping | Low | Small | None |
| 4. KeycapView Decomposition | High | Large | Phases 1-2, snapshot tests |
| 5. Cache Invalidation | Low | Small | None |

Phases 1, 2, 3, and 5 can be done independently in any order. Phase 4 depends on having solid test coverage from the others.

## Existing Test Coverage

Added during the 2026-05-26 session:
- **PR #585**: 9 unit tests — mergeAugmentation (5), floating label visibility (3), VimBindings arrows (1)
- **PR #586**: 4 snapshot tests — base layer HJKL letters, nav keycap arrows (H, J), full nav overlay

## Verification

Each phase ships as its own PR with:
- `swift test` — all existing tests pass
- `KEYPATH_SNAPSHOTS=1 swift test` — all snapshot tests pass
- Manual verification: hold Space (nav), hold Caps (launcher), KindaVim normal/insert, base layer
- No behavior changes — pure structural refactoring
