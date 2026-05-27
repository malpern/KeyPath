# Phase 4: OverlayKeycapView Decomposition Plan

## Overview

Phase 4 of the [overlay rendering refactor](overlay-refactor-plan.md). Breaks `OverlayKeycapView` (2,685 LOC, 32 stored properties, 50+ computed properties, 16 extension files) into focused child views via composition.

Phases 1-3 are prerequisites (completed 2026-05-27):
- Phase 1: FloatingLabelVisibility model (#588)
- Phase 2: LayerMappingBuilder pipeline (#588)
- Phase 3: State grouping in LiveKeyboardOverlayView (#590)

## Current Architecture

The single view handles three fundamentally different rendering modes plus cross-cutting legend styles:

1. **Launcher Mode** (`isLauncherMode`): App icons, URL favicons, transition animations
2. **Layer Mode** (`isLayerMode`): Nav/vim arrows, window management symbols, action icons, collection-colored backgrounds
3. **Base Mode** (default): Standard keycap rendering with shift labels, floating labels, dual-symbol content, multi-legend (JIS/ISO)
4. **Cross-cutting**: Dots legend, blank legend, iconMods legend

### Content Routing (current)

```
keyContent:
  .dots       -> dotsLegendContent          (+DotsLegend)
  .blank      -> EmptyView
  .iconMods   -> iconModsContent            (+IconModsLegend)
  .standard   -> standardKeyContent

standardKeyContent:
  touchId          -> touchIdContent         (+SpecialKeys)
  launcherMode     -> launcherModeContent    (+LauncherMode)
  layerMode        -> layerModeContent       (+ModeContent)
  multiLegend      -> multiLegendContent     (+ModeContent)
  noveltyKey       -> noveltyKeyContent      (+SpecialKeys)
  functionKey      -> functionKeyContent     (+SpecialKeys)
  ...etc per layoutRole
```

## Target Architecture

```
OverlayKeycapView (parent shell, ~350 LOC)
  |-- keycap background, shadows, glow, press animation
  |-- selection/hover highlights
  |-- gesture handling (click, hover, drag)
  |-- accessibility labels
  |-- icon loading lifecycle (onAppear/onChange)
  |-- mode dispatch: which child view to render
  |
  |-- LauncherModeKeycap (~120 LOC, ~10 params)
  |     app icons, favicons, link badges, transition animation
  |     key letter in top-right corner, unmapped key fallback
  |
  |-- LayerModeKeycap (~350 LOC, ~15 params)
  |     nav arrows, vim labels, window SF symbols
  |     action content (system action icons, app icons, favicons)
  |     key letter in top-left corner, collection colors, zone subtitles
  |
  |-- BaseKeycap (~500 LOC, ~18 params)
  |     centered content, dual-symbol, shift labels
  |     bottom-aligned content, narrow modifiers, function keys
  |     arrows, esc, touchId, novelty, app launch, URL, system action
  |     inline layer mapped content, multi-legend (JIS/ISO)
  |
  |-- KeycapRenderingUtilities (~180 LOC)
        sfSymbolForAction, windowActionSymbol, collectionColor, etc.
```

## Parameter Analysis

**Shared by all modes (keycap shell, 15 params):**
`key`, `baseLabel`, `isPressed`, `scale`, `isDarkMode`, `fadeAmount`, `isReleaseFading`, `releaseFadeFromColor`, `isEmphasized`, `isOneShot`, `isHoldActive`, `isSelected`, `isHoveredByRule`, `isInspectorVisible`, `colorway`

**Launcher-specific (6 params):**
`isLauncherMode`, `launcherMapping`, `holdLabel`, `appIcon`, `faviconImage`, `launcherTransition`/`iconVisible`

**Layer-specific (8 params):**
`currentLayerName`, `layerKeyInfo`, `holdLabel`, `customIcon`, `zoneColor`, `zoneSubtitle`, `appIcon`, `faviconImage`

**Base-specific (7 params):**
`useFloatingLabels`, `shiftLabelOverride`, `tapHoldIdleLabel`, `showScoopedHomeRow`, `isKeymapTransitioning`, `isCapsLockOn`, `isLoadingLayerMap`

## Sub-phases

### 4.0: Expand Snapshot Coverage (safety net)

Before any extraction, add snapshot tests for every mode/variant:

**Keycap-level snapshots needed:**
1. Launcher mode with app mapping
2. Launcher mode unmapped key
3. Launcher mode utility key (preservesBaseInLauncher)
4. Layer mode window action (SF symbol)
5. Layer mode unmapped key
6. Layer mode system action
7. Layer mode app launch
8. Layer mode zone subtitle
9. Base layer dual-symbol (e.g., "1" / "!")
10. Base layer function key (F1 + icon)
11. Base layer narrow modifier (fn + globe)
12. Base layer with zone subtitle
13. Inline layer arrow mapping
14. Dots legend alpha key
15. Dots legend modifier
16. IconMods modifier
17. Nav identity mapping (large centered label)

**Full-overlay snapshots:**
18. Full overlay in launcher mode
19. Full overlay on window layer

**Files:** `Tests/KeyPathSnapshotTests/ScenarioSnapshotTests.swift`, support files

### 4.1: Extract Shared Utilities (low risk)

Move pure functions used by multiple modes into `KeycapRenderingUtilities.swift`:
- `sfSymbolForAction(_:)` from `+ActionSymbols.swift`
- `isModifierOrSpecialKey(_:)` from `+ActionSymbols.swift`
- `dynamicTextLabel(_:)` from `+ActionSymbols.swift`
- `windowActionSymbol(from:)` and `windowActionColor(from:)` from `+WindowActions.swift`
- `collectionColor(for:)` from `+CollectionColors.swift`

### 4.2: Extract LauncherModeKeycap (medium risk)

Most self-contained branch. Move from `+LauncherMode.swift`:
- `launcherModeContent`, `launcherKeyLabel`, `launcherAppIcon`
- `launcherFallbackSymbol(for:)`, `launcherLinkBadge(size:)`, `lerp(from:to:progress:)`

### 4.3: Extract LayerModeKeycap (higher risk)

Larger, handles nav arrows + vim labels + window actions + zone subtitles. Move from `+ModeContent.swift`:
- `layerModeContent`, `layerKeyLabel`, `layerActionContent`
- `navIdentityContent`, `zoneSubtitleIcon(_:)`

For unmapped-key fallback paths (arrow, modifier, esc rendering), define simplified inline renderers rather than coupling back to base content.

### 4.4: Extract BaseKeycap (medium risk, largest)

All remaining content. Move from `+LayoutContent.swift`, `+SpecialKeys.swift`, `+ModeContent.swift`:
- `centeredContent`, `dualSymbolContent`, `bottomAlignedContent`
- `narrowModifierContent`, `functionKeyContent`, `arrowContent`, `escKeyContent`
- `touchIdContent`, `noveltyKeyContent`, `appLaunchContent`, `urlMappingContent`
- `multiLegendContent`, `inlineLayerMappedContent`

### 4.5: Clean Up Parent Shell

Delete empty extension files. Surviving extensions:
- `+ContentAndStyling.swift` (shell + mode dispatch)
- `+VisualStyling.swift` (colors, shadows)
- `+DotsLegend.swift`, `+IconModsLegend.swift` (legend styles)
- `+Icons.swift` (icon loading)
- `+LabelClassification.swift` (slimmed)
- `+Preview.swift`, `+Pulse.swift`

## Design Decisions

- **Parent keeps all 32 params.** Child views receive only the 10-18 relevant to their mode.
- **@State stays in parent.** `appIcon`, `faviconImage`, `launcherTransition` passed down as regular params to preserve animation lifecycle.
- **Background color stays in parent.** Mode-dependent, paints keycap shell before content.
- **Each sub-phase is a separate PR** with snapshot test validation.

## Dependency Order

```
4.0 (snapshots) → 4.1 (utilities) → 4.2 (launcher) → 4.3 (layer) → 4.4 (base) → 4.5 (cleanup)
```

4.2 and 4.3 could theoretically parallel but sequential avoids `+ContentAndStyling.swift` merge conflicts.

## Estimated Effort

| Phase | Risk | Effort |
|-------|------|--------|
| 4.0 Snapshot expansion | None | 1-2 days |
| 4.1 Shared utilities | Low | 0.5 day |
| 4.2 LauncherModeKeycap | Medium | 0.5 day |
| 4.3 LayerModeKeycap | Higher | 1 day |
| 4.4 BaseKeycap | Medium | 1-1.5 days |
| 4.5 Cleanup | Low | 0.5 day |
| **Total** | | **4-6 days** |
