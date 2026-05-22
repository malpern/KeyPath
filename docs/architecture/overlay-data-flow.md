# Overlay → Mapper → Gallery Data Flow

The overlay, mapper drawer, and gallery are connected through notifications and shared state. Bugs here are common because the same data takes different paths for display vs. saving.

## Key Rendering Pipeline (Overlay)

```
PhysicalLayout.keys → LayerKeyMapper (simulator) → layerKeyMap[keyCode] → OverlayKeycapView
                                                                              ↓
                                                                   layoutRole determines renderer:
                                                                   .centered → centeredContent (effectiveLabel)
                                                                   .bottomAligned → bottomAlignedContent (wordLabel from LabelMetadata)
                                                                   .escKey → escKeyContent
                                                                   .functionKey → functionKeyWithMappingContent
```

**Label priority in `effectiveLabel`:** holdLabel (if pressed) → tapHoldIdleLabel (if idle on base) → layerKeyInfo.displayLabel → baseLabel (from keymap)

**`tapHoldIdleLabels`**: For tap-hold keys, the simulator returns the *hold* output (it simulates a 50ms press which triggers hold for `tap-hold-press`). The `tapHoldIdleLabels` system overrides this with the *tap* output when the key is idle on the base layer. These labels come from `TapHoldPickerConfig.selectedTapOutput` on enabled collections.

## Mapper Drawer Communication

The mapper receives key selections via `.mapperDrawerKeySelected` notification (not direct binding):
```
OverlayKeycapView click → LiveKeyboardOverlayController.handleKeyClick()
  → posts .mapperDrawerKeySelected with { keyCode, inputKey, outputKey, displayLabel, ... }
  → OverlayMapperSection receives notification → calls viewModel.setInputFromKeyClick()
```

**Critical distinction:** `outputKey` is the kanata key name (e.g., "lctl") used for saving rules. `displayLabel` is the human-readable label (e.g., "✦" for Hyper). The mapper uses `outputKey` for the data/save path and `displayLabel` for visual override. Mixing these up causes config validation errors ("Unknown key/action: ✦").

## Conflict Resolution

When saving a rule that conflicts with an existing rule collection:
- **Mapper:** uses `autoResolveConflicts: true` — the new mapping silently wins
- **Pack installer:** uses `autoResolveConflicts: true` — the pack silently wins
- **Rules tab (ActiveRulesView, RulesSummaryView):** shows a conflict resolution dialog via `onConflictResolution` callback on `RuntimeCoordinator`

## Layer Map Refresh Chain

```
Rule change → regenerateConfigFromCollections() → posts .ruleCollectionsChanged
  → KeyboardVisualizationViewModel.setupRuleCollectionsObserver() receives it
  → invalidateLayerMappings() → rebuildLayerMappingForLayer()
  → simulator re-runs → layerKeyMap updated → SwiftUI re-renders overlay
```

## LabelMetadata (Display Labels for Wide Keys)

`LabelMetadata.forLabel()` converts symbols/key names to word labels for bottom-aligned keys (shift, return, capslock, etc.). It is case-insensitive for multi-character labels — "Esc", "esc", "ESC" all match. Single-character symbols (⇧, ⎋, ⇪) match directly.
