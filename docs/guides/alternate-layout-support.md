# Alternate Keyboard Layout Support

**Status:** Proposed
**Created:** December 2025
**Priority:** Medium (UX improvement for ~5-10% of power users)

## Problem Statement

KeyPath displays key labels using QWERTY letter names throughout the UI. For users of alternate keyboard layouts (Dvorak, Colemak, Workman, etc.), these labels don't match what's printed on their keycaps, creating confusion.

**Example:** The Numpad Layer shows "J K L → 4 5 6". A Dvorak user looks at their keyboard and sees H, T, N in those physical positions. They must mentally translate QWERTY positions to find the correct keys.

**Important distinction:**
- The **mappings themselves** are correct and layout-agnostic (they operate on physical key positions)
- Only the **UI labels** need to change to match the user's keycaps

## Proposed Solution

Create a centralized `KeyLabelFormatter` that transforms physical key positions to display labels based on the user's layout preference.

```swift
// Usage
KeyLabelFormatter.shared.label(forPhysicalKey: "j") // → "J" (QWERTY)
KeyLabelFormatter.shared.label(forPhysicalKey: "j") // → "H" (Dvorak)
KeyLabelFormatter.shared.label(forPhysicalKey: "j") // → "N" (Colemak)
```

## Affected Components

| Component | Priority | Notes |
|-----------|----------|-------|
| Symbol Layer grid | High | Shows full keyboard transformation |
| Numpad Layer grid | High | Shows left/right hand key positions |
| Overlay keyboard | High | Floating keyboard shows all keys |
| Vim Navigation table | Medium | HJKL labels |
| Home Row Mods visualization | Medium | ASDF/JKL; labels |
| Window Snapping table | Medium | HJKL, YU, BN labels |
| MiniPresetCard previews | Medium | Home row preview |
| Custom Rules list | Medium | Input/output key display |
| Custom Rule Editor | Low | Key picker autocomplete |

## Supported Layouts

### Phase 1 (covers ~95% of alt-layout users)
- QWERTY (default)
- Dvorak
- Colemak
- Colemak-DH

### Phase 2 (if requested)
- Workman
- Norman
- AZERTY (French)
- QWERTZ (German)

## Technical Design

### 1. Layout Enum

```swift
enum KeyboardLayout: String, Codable, CaseIterable {
    case qwerty
    case dvorak
    case colemak
    case colemakDH

    var displayName: String {
        switch self {
        case .qwerty: "QWERTY"
        case .dvorak: "Dvorak"
        case .colemak: "Colemak"
        case .colemakDH: "Colemak-DH"
        }
    }
}
```

### 2. Physical Position Mapping

Map QWERTY key names (our canonical physical position identifiers) to each layout's letters:

```swift
// Physical position "j" (QWERTY J position) maps to:
let positionMappings: [KeyboardLayout: [String: String]] = [
    .qwerty: ["j": "J", "k": "K", "l": "L", ...],
    .dvorak: ["j": "H", "k": "T", "l": "N", ...],
    .colemak: ["j": "N", "k": "E", "l": "I", ...],
    .colemakDH: ["j": "N", "k": "E", "l": "I", ...],
]
```

### 3. KeyLabelFormatter Service

```swift
@MainActor
final class KeyLabelFormatter {
    static let shared = KeyLabelFormatter()

    /// Current layout preference (from UserDefaults)
    var currentLayout: KeyboardLayout {
        get { /* read from preferences */ }
        set { /* write to preferences, notify observers */ }
    }

    /// Convert physical key position to display label
    func label(forPhysicalKey key: String) -> String {
        guard let mappings = positionMappings[currentLayout],
              let label = mappings[key.lowercased()] else {
            return key.uppercased() // fallback to raw key
        }
        return label
    }

    /// Convert multiple keys (e.g., "hjkl" → "HTNS" for Dvorak)
    func labels(forPhysicalKeys keys: [String]) -> [String] {
        keys.map { label(forPhysicalKey: $0) }
    }
}
```

### 4. Settings UI

Add a "Keyboard Layout" picker in Settings → General:

```
Keyboard Layout
[QWERTY ▾]

Labels throughout KeyPath will match your keyboard.
Mappings work the same regardless of this setting.
```

### 5. System Detection (Optional Enhancement)

Could auto-detect from system input source:
```swift
func detectSystemLayout() -> KeyboardLayout? {
    guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let layoutID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
        return nil
    }
    // Map known layout IDs to our enum
}
```

However, this is unreliable (users may have multiple layouts, custom layouts, etc.). A manual preference is more robust.

## Migration & Compatibility

- Default to QWERTY (current behavior)
- Existing users see no change unless they opt-in
- Setting stored in UserDefaults, not in config file
- No impact on actual key mappings or Kanata config generation

## UI Copy Updates

When a non-QWERTY layout is selected, remove or update the disclaimer:

**QWERTY selected:**
> "Keys labeled by physical position (QWERTY). Works with any keyboard layout."

**Other layout selected:**
> "Keys labeled to match your Dvorak keyboard."

Or simply remove the disclaimer entirely when labels match.

## Testing Considerations

1. Unit tests for position mappings (verify all keys mapped for each layout)
2. Verify label formatter returns correct values for each layout
3. UI tests: toggle layout preference, verify labels update throughout app
4. Edge cases: unknown keys, mixed-case input, special keys (symbols, modifiers)

## Out of Scope

- **Custom layout editor** - Too complex, users can request specific layouts
- **Per-app layout detection** - System layout may differ from app layout
- **Automatic layout switching** - Keep it simple, one preference
- **Changing the actual mappings** - This feature is display-only

## Estimated Effort

| Task | Estimate |
|------|----------|
| KeyboardLayout enum + mappings | 1-2 hours |
| KeyLabelFormatter service | 1 hour |
| Settings UI | 1 hour |
| Update Symbol/Numpad grids | 1 hour |
| Update overlay keyboard | 2 hours |
| Update other components | 2-3 hours |
| Testing | 2 hours |
| **Total** | **10-12 hours** |

## References

- [DreymaR's Big Bag](https://dreymar.colemak.org/) - Comprehensive alt-layout resources
- [Colemak Mods](https://colemakmods.github.io/ergonomic-mods/) - Colemak-DH and extensions
- [Miryoku](https://github.com/manna-harbour/miryoku) - Layout-agnostic keymap design

## Decision

- [ ] Approve for implementation
- [ ] Defer (current disclaimer is sufficient)
- [ ] Modify scope (specify changes)
