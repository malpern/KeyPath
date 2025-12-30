# RuleCollection Configuration Pattern

The `RuleCollection` model uses a **discriminated union pattern** via `RuleCollectionConfiguration` to handle different display styles with type-safe associated data.

## Why This Pattern?

- Different display styles (list, picker, home row mods) need different data
- Previously, `RuleCollection` had 15+ optional fields where only some applied to each style
- Now each style carries exactly the data it needs as associated values

## The Configuration Enum

```swift
public enum RuleCollectionConfiguration: Codable, Equatable, Sendable {
    case list                                    // Simple list display
    case table                                   // Table with columns
    case singleKeyPicker(SingleKeyPickerConfig)  // Caps Lock → X picker
    case homeRowMods(HomeRowModsConfig)          // Visual keyboard customization
    case tapHoldPicker(TapHoldPickerConfig)      // Tap → Esc, Hold → Hyper
    case layerPresetPicker(LayerPresetPickerConfig) // Choose layer presets
}
```

## Convenience Accessors

```swift
collection.configuration.displayStyle           // → RuleCollectionDisplayStyle
collection.configuration.singleKeyPickerConfig  // → SingleKeyPickerConfig?
collection.configuration.tapHoldPickerConfig    // → TapHoldPickerConfig?
collection.configuration.homeRowModsConfig      // → HomeRowModsConfig?
collection.configuration.layerPresetPickerConfig // → LayerPresetPickerConfig?
```

## Mutating Helpers

```swift
collection.configuration.updateSelectedOutput("esc")
collection.configuration.updateSelectedTapOutput("esc")
collection.configuration.updateSelectedHoldOutput("hyper")
collection.configuration.updateHomeRowModsConfig(newConfig)
collection.configuration.updateSelectedPreset("preset-id")
```

## JSON Format (Discriminated Union)

```json
{
  "configuration": {
    "type": "singleKeyPicker",
    "inputKey": "caps",
    "presetOptions": [...],
    "selectedOutput": "esc"
  }
}
```

## Migration

The `RuleCollection.init(from:)` decoder handles legacy JSON (with flat `displayStyle`, `pickerInputKey`, etc. fields) and automatically migrates to the new `configuration` format on load.

## Key Files

| File | Purpose |
|------|---------|
| `RuleCollectionModels.swift` | Core `RuleCollection` struct |
| `RuleCollectionConfiguration.swift` | The discriminated union enum and config structs |
| `RuleCollectionCatalog.swift` | Built-in collection definitions using the new pattern |
