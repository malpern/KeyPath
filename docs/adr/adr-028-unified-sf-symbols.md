# ADR-028: Unified SF Symbol Resolution via SystemActionInfo

**Status:** Accepted
**Date:** 2026-01-04

## Context

SF Symbol lookups for system actions and media keys were scattered across multiple files:

| Location | Purpose |
|----------|---------|
| `IconResolverService.systemActionSymbols` | Dictionary of push-msg system actions |
| `LabelMetadata.sfSymbol(forOutputLabel:)` | Large switch statement for all media/system labels |
| `CustomRuleValidator.SystemActionSuggestion` | Complete duplicate struct with same data |
| `CustomRulesView.SystemActionChip.actionInfo` | Partial duplicate (spotlight, mission-control, etc.) |

This caused:
1. **Drift** - Symbols could get out of sync between files
2. **Bugs** - Media keys like "brup" weren't recognized on app restart because they were treated as simple remaps instead of system actions
3. **Maintenance burden** - Adding a new action required updating 4+ files

## Decision

Establish `SystemActionInfo.allActions` in `MapperActionTypes.swift` as the **single source of truth** for all system action and media key metadata:

```swift
public static let allActions: [SystemActionInfo] = [
    // Push-msg system actions
    SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass"),
    // ...
    // Media keys (direct keycodes)
    SystemActionInfo(id: "brightness-up", name: "Brightness Up", sfSymbol: "sun.max",
                     kanataKeycode: "brup", simulatorName: "BrightnessUp"),
    // ...
]
```

All other components delegate to `SystemActionInfo.find(byOutput:)`:

```
                    ┌─────────────────────────────────┐
                    │  SystemActionInfo.allActions    │
                    │  (Single Source of Truth)       │
                    └─────────────────────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│ IconResolverService │  │  LabelMetadata      │  │ CustomRuleValidator │
│ .systemActionSymbol │  │  .sfSymbol(for      │  │ .systemActions      │
│    (for:)           │  │   OutputLabel:)     │  │                     │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

## Implementation

### 1. IconResolverService (was: hardcoded dictionary)

```swift
// Before
private static let systemActionSymbols: [String: String] = [
    "spotlight": "magnifyingglass",
    // ... 12 entries, missing media keys!
]

// After
func systemActionSymbol(for actionId: String) -> String? {
    SystemActionInfo.find(byOutput: actionId)?.sfSymbol
}
```

### 2. LabelMetadata (was: 30-case switch statement)

```swift
// Before
switch cleanLabel {
case "MediaPlayPause", "Play/Pause", "pp": return "playpause"
// ... 30+ cases

// After
if let action = SystemActionInfo.find(byOutput: cleanLabel) {
    return action.sfSymbol
}
// Only edge cases remain (hotkey combos like "⌃⌘F")
```

### 3. CustomRuleValidator (was: duplicate struct)

```swift
// Before
public struct SystemActionSuggestion { ... } // 50 lines, identical to SystemActionInfo

// After
public typealias SystemActionSuggestion = SystemActionInfo
public static var systemActions: [SystemActionInfo] { SystemActionInfo.allActions }
```

### 4. augmentWithPushMsgActions (critical fix)

Media keys now create `LayerKeyInfo.systemAction` instead of `.mapped`:

```swift
// Before - media keys treated as simple remaps (no icon!)
actionByInput[input] = .mapped(displayLabel: "Brightness Up", outputKey: "brup", ...)

// After - media keys properly identified
if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
    actionByInput[input] = .systemAction(action: systemAction.id, description: systemAction.name)
}
```

## Consequences

### Positive

- **Single update point** - Add/modify actions only in `SystemActionInfo.allActions`
- **No more drift** - All components use the same data
- **Media keys work on restart** - `systemActionIdentifier` is properly set
- **Test coverage** - 60 tests verify the unified system

### Negative

- **SystemActionInfo.find() called frequently** - Minor performance impact (array scan), could optimize with dictionary if needed

## Files Changed

| File | Change |
|------|--------|
| `MapperActionTypes.swift` | Source of truth (unchanged, already correct) |
| `IconResolverService.swift` | Removed dictionary, delegates to SystemActionInfo |
| `KeycapLayoutRole.swift` | Removed switch cases, delegates to SystemActionInfo |
| `CustomRuleValidator.swift` | Typealias, delegates to SystemActionInfo |
| `CustomRulesView.swift` | SystemActionChip uses SystemActionInfo |
| `KeyboardVisualizationViewModel.swift` | Media keys create .systemAction not .mapped |

## Kept Separate (Different Purpose)

| Component | Reason |
|-----------|--------|
| `LabelMetadata.sfSymbol(forKeyCode:)` | Physical F-key icons by hardware keyCode |
| `FunctionKeysView.FunctionKeyInfo` | Physical function row UI element |
| `KeyIconRegistry` | Custom icon registry for push-msg "icon:name" |

## Related

- ADR-024: Custom Key Icons and Emphasis - defines icon registry for push-msg
- ADR-023: No Config Parsing - uses TCP messages for key info
