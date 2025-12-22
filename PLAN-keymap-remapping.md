# Implementation Plan: Active Keymap Remapping

## Overview

Transform the overlay keymap selector from a visual-only preference into an active keyboard remapping feature. When users select Colemak/Dvorak/Workman, KeyPath will generate Kanata rules to remap the physical QWERTY keys to that layout.

## Current State

- `LogicalKeymap` defines `coreLabels` (30-key letter block) and `extraLabels` (punctuation)
- Keymap selection stored in `@AppStorage("overlayKeymapId")`
- Selection only changes overlay display labels, no actual remapping
- `RuleCollectionsManager` handles all rule management and config generation
- `ConfigurationService.saveConfiguration()` generates Kanata config from rules

## Architecture Decision

**Approach: Create a special "Keymap Layout" RuleCollection**

Rather than custom rules (which are per-key), we'll create a managed RuleCollection that:
- Is auto-generated based on `LogicalKeymap` selection
- Stored separately from user-created collections
- Has special conflict handling (warns if user has custom rules on same keys)
- Can be easily toggled on/off

## Implementation Steps

### Phase 1: Data Model Updates

**1.1 Add KeymapLayoutCollection model**

Location: `Sources/KeyPathAppKit/Models/KeymapLayoutCollection.swift` (new file)

```swift
struct KeymapLayoutCollection {
    let keymapId: String           // "colemak-dh", "dvorak", etc.
    let includePunctuation: Bool
    var isEnabled: Bool

    // Generate mappings from LogicalKeymap
    func generateMappings() -> [KeyMapping]
}
```

**1.2 Extend RuleCollectionsManager**

Add properties:
- `var activeKeymapCollection: KeymapLayoutCollection?`
- Track keymap state separate from user collections

Add methods:
- `func setActiveKeymap(_ keymapId: String?, includePunctuation: Bool) async`
- `func keymapConflicts(with customRules: [CustomRule]) -> [ConflictInfo]`

### Phase 2: Mapping Generation

**2.1 Create KeymapMappingGenerator**

Location: `Sources/KeyPathAppKit/Services/KeymapMappingGenerator.swift` (new file)

```swift
struct KeymapMappingGenerator {
    /// Generate key mappings to remap QWERTY to target layout
    /// Returns empty array for QWERTY (no remapping needed)
    static func generateMappings(
        from sourceLayout: LogicalKeymap,  // Always QWERTY
        to targetLayout: LogicalKeymap,
        includePunctuation: Bool
    ) -> [KeyMapping]
}
```

Logic:
1. For each key in target layout's `coreLabels`:
   - Find the physical key code
   - Find what QWERTY outputs for that physical key
   - If different from target, create mapping: `physicalKey -> targetOutput`
2. If QWERTY selected, return empty (no remapping)
3. If includePunctuation, also process `extraLabels`

**Example for Colemak:**
- Physical 'E' key (keyCode 14) outputs 'e' in QWERTY
- Colemak wants 'f' on that physical position
- Generate: `e -> f` (input is QWERTY label, output is Colemak label)

### Phase 3: Config Integration

**3.1 Update ConfigurationService**

Modify `saveConfiguration()` to accept optional keymap layout:

```swift
func saveConfiguration(
    ruleCollections: [RuleCollection],
    customRules: [CustomRule],
    keymapLayout: KeymapLayoutCollection?  // NEW
) async throws
```

The keymap mappings should be rendered:
- As a distinct section in the config (commented for clarity)
- BEFORE other rules (so they can be overridden by user customizations)

**3.2 Update RuleCollectionsManager.regenerateConfigFromCollections()**

Include keymap layout when calling ConfigurationService.

### Phase 4: Conflict Detection

**4.1 Add keymap-specific conflict checks**

In `RuleCollectionsManager`:

```swift
func keymapConflicts(with customRules: [CustomRule]) -> [ConflictInfo] {
    // Check if any custom rules target keys that keymap will remap
    // Return list of conflicts for UI warning
}
```

**4.2 UI Warning Flow**

When user selects a non-QWERTY layout:
1. Check for conflicts with existing custom rules
2. If conflicts exist, show alert:
   - "Switching to Colemak will affect these custom mappings: [list]"
   - Options: "Apply Anyway" / "Cancel"
3. If no conflicts or user confirms, proceed with remap

### Phase 5: UI Integration

**5.1 Update OverlayInspectorPanel**

When keymap selection changes:
```swift
.onChange(of: selectedKeymapId) { oldValue, newValue in
    Task {
        await applyKeymapLayout(newValue)
    }
}

func applyKeymapLayout(_ keymapId: String) async {
    // 1. Check conflicts
    // 2. Show warning if needed
    // 3. Call RuleCollectionsManager.setActiveKeymap()
    // 4. Sound plays automatically via regenerateConfigFromCollections()
}
```

**5.2 Inject RuleCollectionsManager dependency**

The OverlayInspectorPanel needs access to RuleCollectionsManager to apply changes.

### Phase 6: Persistence

**6.1 Store active keymap in RuleCollectionStore**

Add to stored state:
```swift
struct StoredRuleState: Codable {
    var collections: [RuleCollection]
    var activeKeymapId: String?        // NEW
    var keymapIncludePunctuation: Bool // NEW
}
```

**6.2 Bootstrap loading**

On app launch, restore keymap layout from stored state.

### Phase 7: Unit Tests

**7.1 KeymapMappingGeneratorTests**

Location: `Tests/KeyPathAppKitTests/KeymapMappingGeneratorTests.swift`

Tests:
- `testQWERTYGeneratesNoMappings()` - QWERTY -> QWERTY = empty
- `testColemakGeneratesCorrectMappings()` - Verify e->f, r->p, etc.
- `testDvorakGeneratesCorrectMappings()` - Verify full Dvorak layout
- `testIncludePunctuationAddsMappings()` - With/without punctuation toggle
- `testOnlyDifferentKeysAreMapped()` - Keys that match QWERTY aren't remapped

**7.2 KeymapConflictDetectionTests**

Location: `Tests/KeyPathAppKitTests/KeymapConflictDetectionTests.swift`

Tests:
- `testNoConflictsWithEmptyCustomRules()`
- `testDetectsConflictWithCustomRule()` - Custom rule on 'e', keymap remaps 'e'
- `testNoConflictOnUnaffectedKeys()` - Custom rule on 'z', keymap doesn't touch 'z'

**7.3 KeymapIntegrationTests**

Location: `Tests/KeyPathAppKitTests/KeymapIntegrationTests.swift`

Tests:
- `testSetActiveKeymapRegeneratesConfig()`
- `testKeymapPersistedAcrossRestart()`
- `testDisablingKeymapRemovesFromConfig()`

## File Changes Summary

### New Files
- `Sources/KeyPathAppKit/Models/KeymapLayoutCollection.swift`
- `Sources/KeyPathAppKit/Services/KeymapMappingGenerator.swift`
- `Tests/KeyPathAppKitTests/KeymapMappingGeneratorTests.swift`
- `Tests/KeyPathAppKitTests/KeymapConflictDetectionTests.swift`
- `Tests/KeyPathAppKitTests/KeymapIntegrationTests.swift`

### Modified Files
- `Sources/KeyPathAppKit/Services/RuleCollectionsManager.swift` - Add keymap management
- `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift` - Accept keymap in save
- `Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayView.swift` - Wire up selection to remap
- `Sources/KeyPathAppKit/Infrastructure/Persistence/RuleCollectionStore.swift` - Persist keymap state

## Conflict Handling Rules

1. **QWERTY selected**: No remapping applied, all custom rules work normally
2. **Non-QWERTY selected**:
   - Keymap mappings applied first (lower priority)
   - Custom rules can override specific keys (higher priority)
   - Warning shown if custom rule targets a remapped key
3. **User disables keymap**: Reverts to QWERTY behavior

## Sound Effects

- **Success**: `SoundManager.playTinkSound()` - via existing `regenerateConfigFromCollections()` flow
- **Conflict Warning**: `SoundManager.playWarningSound()` - when conflicts detected
- **Error**: `SoundManager.playErrorSound()` - if config generation fails

## Edge Cases

1. **User has existing custom rules**: Warn, allow override
2. **Invalid keymap ID**: Fall back to QWERTY (no remap)
3. **Keymap + custom rule on same key**: Custom rule wins (applied after keymap)
4. **Momentary layer activator on remapped key**: Should still work (activator is physical key)

## Testing Checklist

- [ ] QWERTY selection produces no keymap mappings
- [ ] Colemak selection remaps correct keys
- [ ] Dvorak selection remaps correct keys (including punctuation positions)
- [ ] Workman selection remaps correct keys
- [ ] Include punctuation toggle works correctly
- [ ] Conflict detection identifies affected custom rules
- [ ] Warning dialog appears when conflicts exist
- [ ] Config change sound plays on successful remap
- [ ] Keymap persists across app restart
- [ ] Disabling keymap removes mappings from config
- [ ] Custom rules can override keymap mappings
