# Window Management

Window snapping via the Accessibility API (`AXUIElement`) and Space movement via private CGS APIs. Requires Accessibility permission (same as Kanata).

## Activation

Leader → w → action key (chained layer activation)

## Window Actions

| Key | Action | Description |
|-----|--------|-------------|
| h | `window:left` | Left half of screen |
| l | `window:right` | Right half of screen |
| m | `window:maximize` | Maximize/Restore toggle |
| c | `window:center` | Center window |
| y | `window:top-left` | Top-left quarter |
| u | `window:top-right` | Top-right quarter |
| b | `window:bottom-left` | Bottom-left quarter |
| n | `window:bottom-right` | Bottom-right quarter |
| [ | `window:previous-display` | Move to previous display |
| ] | `window:next-display` | Move to next display |
| a | `window:previous-space` | Move to previous Space |
| s | `window:next-space` | Move to next Space |
| z | `window:undo` | Restore previous position |

## Key Layout Mnemonic (vim-adjacent)

```
  y   u      (top-left, top-right)
h   l        (left half, right half)
  b   n      (bottom-left, bottom-right)

a   s        (prev space, next space)
[ ]          (prev display, next display)
```

## Implementation

| File | Purpose |
|------|---------|
| `WindowManager.swift` | Accessibility API wrapper for window positioning |
| `CGSPrivate.swift` | Private CoreGraphics Services API declarations for Space management |
| `SpaceManager` | Enumerates spaces and moves windows between them |
| `ActionDispatcher` | Routes `window:*` push-msg to WindowManager |
| `RuleCollectionCatalog.windowSnapping` | Collection with chained layer activation |

## Private API Note

Space movement uses undocumented but stable CGS APIs (same as Amethyst, alt-tab-macos). These work with notarization but could break in future macOS versions.
