# MAL-61: Context HUD Implementation Plan

## Context

KeyPath currently shows available key mappings only through the full keyboard overlay, which is information-dense and always shows the entire keyboard. Many users want a lighter-weight, contextual display that appears automatically when they activate a layer, one-shot, or mode -- showing just the available commands for that context. This is the "Context HUD": a standalone frosted-glass floating window that surfaces available actions on demand.

MAL-56 (Overlay Context Integration) already delivered collection-aware color-coding and layer key mapping data. The HUD builds on this foundation using the same `LayerKeyMapper` data and notification system, but presents it in a minimal, auto-dismissing format.

---

## Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| **Value** | **High** | Core UX differentiator -- most keyboard remappers have no command discovery. Directly addresses the "I activated a layer but forgot what's on it" problem. Enables "HUD only" mode for users who find the full overlay too heavy. |
| **Effort** | **Medium** (6-8 days) | 5 phases, ~10 new files. Follows established patterns (floating windows, notifications, frosted glass). Custom views (window snap grid, launcher icons) add complexity but reuse existing data sources. |
| **Risk** | **Low-Medium** | No changes to core config generation or Kanata integration. Main risks: (1) window z-ordering edge cases with overlay, (2) timing of async layer key data availability, (3) rapid layer switch debouncing. All mitigated by existing patterns. |

---

## Architecture

```
Notification Center (.kanataLayerChanged, .kanataOneShotActivated, .kanataKeyInput)
         │
         ▼
ContextHUDController (singleton, @MainActor)
  ├── checks PreferencesService.contextHUDDisplayMode
  ├── fetches [UInt16: LayerKeyInfo] from LayerKeyMapper cache
  ├── resolves HUDContentStyle via HUDContentResolver
  ├── manages ContextHUDWindow lifecycle
  └── manages dismiss timer (timeout, key press, Esc, context change)
         │
         ▼
ContextHUDWindow (NSWindow, .floating+1, click-through)
  └── NSHostingView → ContextHUDView (SwiftUI)
       ├── DefaultListView   (keycap + label, grouped by collection)
       ├── WindowSnapView    (snap zone grid)
       ├── LauncherView      (app icon grid)
       └── SymbolView        (symbol grid)
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 days)

**New files:**

| File | Purpose |
|------|---------|
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDController.swift` | Singleton: notification subscriptions, window lifecycle, dismiss timer, positioning |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDWindow.swift` | NSWindow subclass: `canBecomeKey=false`, `.floating+1` level, `ignoresMouseEvents=true`, frosted glass bg |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDViewModel.swift` | `@Observable`: layerName, style, groupedEntries. Transforms `[UInt16: LayerKeyInfo]` into `[HUDKeyGroup]` |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDView.swift` | Root SwiftUI view with `AppGlassBackground(style: .sheetBold)`, layer name header, content switch |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDDefaultListView.swift` | Vertical list: keycap chip + action label, grouped by collection with color-coded headers |
| `Sources/KeyPathAppKit/UI/ContextHUD/HUDKeyEntry.swift` | Model structs: `HUDKeyEntry` (keycap, action, icon, color) and `HUDKeyGroup` (name, color, entries) |

**Key decisions:**
- Window positioned at **lower 1/3 center** of `NSScreen.main.visibleFrame`
- Fade in: scale(0.95->1.0) + alpha(0->1) over 0.15s easeOut (matches overlay pattern)
- Fade out: scale(1.0->0.95) + alpha(1->0) over 0.12s easeIn
- Filter out transparent keys; group remaining by `collectionId` -> `RuleCollection.name`
- Sort entries within groups by physical key position (row-major)
- Base layer -> dismiss HUD; non-base layer -> show HUD

**Modified files:**
- `Sources/KeyPathAppKit/App.swift` or startup path -- initialize `ContextHUDController.shared`

### Phase 2: Settings & Display Mode (1 day)

**Modified files:**

| File | Change |
|------|--------|
| `Sources/KeyPathAppKit/Services/PreferencesService.swift` | Add `contextHUDDisplayMode: ContextHUDDisplayMode` (default: `.both`) and `contextHUDTimeout: TimeInterval` (default: 3.0s, range 1-10s) backed by UserDefaults |
| `Sources/KeyPathAppKit/UI/SettingsView+General.swift` | New "Context HUD" section: segmented picker (Overlay Only / HUD Only / Both) + timeout slider |

**New type:**
```swift
enum ContextHUDDisplayMode: String, CaseIterable {
    case overlayOnly, hudOnly, both
}
```

Wire `ContextHUDController` to check `displayMode` before showing. If `overlayOnly`, skip HUD. If `hudOnly`, potentially suppress the overlay's layer indicator window.

### Phase 3: Content Resolution & Custom Views (2-3 days)

**New files:**

| File | Purpose |
|------|---------|
| `Sources/KeyPathAppKit/UI/ContextHUD/HUDContentResolver.swift` | Maps `(layerName, keyMap, collections)` -> `HUDContentStyle` by checking collection IDs against known catalogs |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDWindowSnapView.swift` | Compact snap-zone grid with key labels. Simplified version of `WindowSnappingView.MonitorCanvas` |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDLauncherView.swift` | App icon grid with key labels. Uses `IconResolverService` for icons |
| `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDSymbolView.swift` | Symbol grid with key triggers |

**Resolution logic:**
- Layer name contains "window" or "snap" -> `.windowSnappingGrid`
- Layer is "launcher" or keys contain `appLaunchIdentifier` -> `.launcherIcons`
- Layer is "sym" or "symbol" -> `.symbolPicker`
- Default -> `.defaultList`

### Phase 4: Dismissal Polish (0.5 days)

All four dismiss triggers, handled in `ContextHUDController`:

1. **Mapped key press**: `.kanataKeyInput` observer checks if key is in current `layerKeyMap` -> dismiss
2. **Timeout**: `Task.sleep` with cancellation token, configurable via `PreferencesService.contextHUDTimeout`
3. **Escape**: `.kanataKeyInput` where key == `"esc"` -> dismiss
4. **Context change**: `.kanataLayerChanged` -> show new content or dismiss if returning to base

### Phase 5: Edge Cases & Polish (1 day)

- **Multi-display**: Position on `NSScreen.main` (screen with active window)
- **Rapid layer switching**: Cancel pending animations, replace content immediately
- **One-shot coordination**: Share `OneShotLayerOverrideState` logic from `LiveKeyboardOverlayController` to avoid base->override->base flicker
- **Z-ordering**: HUD at `.floating + 1` (above overlay, same as `TooltipWindowController`)
- **Accessibility**: `accessibilityRole = .popover`, `accessibilityLabel = "Context HUD: {layerName}"`
- **Dark/light mode**: Frosted glass adapts automatically; verify collection color contrast

---

## Key Patterns to Reuse

| Pattern | Source File | What to Reuse |
|---------|------------|---------------|
| Floating window lifecycle | `UI/LayerIndicatorWindow.swift` | Singleton manager + timer dismiss + fade animation |
| Notification subscriptions | `UI/Overlay/LiveKeyboardOverlayController.swift:261-287` | `.kanataLayerChanged` observer pattern |
| Frosted glass background | `UI/Style/AppGlass.swift` | `AppGlassBackground(style: .sheetBold)` = `.hudWindow` material |
| Layer key data | `Services/LayerKeyMapper.swift` | `getMapping(for:configPath:layout:collections:)` -> `[UInt16: LayerKeyInfo]` |
| Collection color routing | `UI/Overlay/OverlayKeycapView+CollectionColors.swift` | Color mapping by collectionId |
| Settings property pattern | `Services/PreferencesService.swift` | `@Observable` + UserDefaults didSet pattern |
| Window factory | `UI/Overlay/OverlayWindowFactory.swift` | `.borderless`, `.floating`, `canJoinAllSpaces` config |
| One-shot override | `UI/Overlay/LiveKeyboardOverlayController.swift` | `OneShotLayerOverrideState` to avoid flicker |

---

## Verification

1. **Unit tests**: `ContextHUDControllerTests` (show/dismiss logic, timer, notification handling), `HUDContentResolverTests` (style resolution), `ContextHUDViewModelTests` (grouping, filtering, sorting)
2. **Manual testing**:
   - Activate Nav layer -> HUD appears with Vim keys grouped by collection
   - Activate Window layer -> HUD shows snap zone grid
   - Activate Launcher -> HUD shows app icons
   - Press mapped key -> HUD dismisses
   - Press Esc -> HUD dismisses
   - Wait timeout -> HUD auto-dismisses
   - Switch layers rapidly -> no flicker, content updates cleanly
   - Settings: toggle Overlay Only / HUD Only / Both -> verify behavior
   - Settings: adjust timeout slider -> verify timing changes
3. **Build verification**: `SKIP_NOTARIZE=1 ./build.sh` compiles without errors
4. **Test suite**: `swift test` passes
