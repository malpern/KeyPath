# ADR-024: Custom Key Icons and Emphasis via push-msg

**Status:** Partial Implementation
**Date:** 2024

## Context

Users want to customize the overlay with:
- Custom icons on keys (SF Symbols, app icons)
- Visual emphasis on important keys (HJKL in vim layer)

## Decision

Use Kanata's `push-msg` action to communicate customization from config to KeyPath.

## Status (v1.0.0-beta4)

| Feature | Status |
|---------|--------|
| Key Emphasis | ✅ Implemented |
| Custom Icons | ⚠️ Infrastructure only, display deferred |

## Key Emphasis

### Syntax
```lisp
(defalias
  nav-on (multi
           (layer-while-held nav)
           (push-msg "emphasis:h,j,k,l"))
)
```

### Flow
1. Layer activates, sends `(push-msg "emphasis:h,j,k,l")`
2. Kanata sends `{"MessagePush":{"message":"emphasis:h,j,k,l"}}`
3. KeyPath parses comma-separated key names, maps to key codes
4. Overlay renders emphasized keys with visual distinction
5. Emphasis clears on layer change, or via `(push-msg "emphasis:clear")`

### Implementation
- `KeyboardVisualizationViewModel.customEmphasisKeyCodes` - state tracking
- `.kanataMessagePush` notification infrastructure
- Message parsing: `emphasis:h,j,k,l` and `emphasis:clear`
- Visual treatment: Orange background

## Custom Icons

### Syntax
```lisp
(defalias
  vim-left (multi left (push-msg "icon:arrow-left"))
  launch-safari (multi (push-msg "launch:safari") (push-msg "icon:safari"))
)
```

### Icon Registry
```swift
let iconRegistry: [String: IconSource] = [
    "arrow-left": .sfSymbol("arrow.left"),
    "safari": .appIcon("Safari"),
    // 50+ mappings
]
```

### Design Challenge

The `push-msg` protocol doesn't include key context. When Kanata sends:
```json
{"MessagePush":{"message":"icon:arrow-left"}}
```
We receive the icon name but not which key sent it.

### Possible Solutions (Not Yet Implemented)

1. **Extract from layer mapping** (recommended)
   - During `LayerKeyMapper.buildMapping()`, parse output strings for `(push-msg "icon:X")`
   - Store icon name in `LayerKeyInfo`
   - ~2-3 hours effort

2. **Track most-recent key**
   - Fragile timing, not recommended

3. **Upstream Kanata change**
   - Add key context to MessagePush events

4. **Scope reduction**
   - Use icons only for app-launch actions

## Files Involved

- `KeyboardVisualizationViewModel.swift` - has `customIcons` state (unused)
- `KeyIconRegistry.swift` - 50+ icon mappings ready
- `LayerKeyMapper.swift` - needs icon extraction logic
- `LayerKeyInfo.swift` - needs `iconName` field
- `OverlayKeycapView.swift` - needs icon rendering

## Benefits

- Config stays simple (semantic names, not paths or bundle IDs)
- KeyPath controls rendering (can update visuals without config changes)
- Extensible (add emoji, custom images, animations later)
- Follows ADR-023 (no config parsing - uses TCP messages)
