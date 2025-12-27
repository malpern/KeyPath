# ADR-025: Configuration Management - One-Way Write with Segmented Ownership

**Status:** Accepted
**Date:** 2024

## Context

Managing keyboard remapping configuration involves:
- Rule collections (Vim, Caps Lock, etc.) with enable/disable state
- Custom user-defined rules
- The actual `keypath.kbd` file that Kanata reads
- Runtime state (active layer) from Kanata via TCP

## Decision

JSON stores are the source of truth with **one-way generation** to config file.

```
┌─────────────────────────────────────────────────────────┐
│            SOURCE OF TRUTH (JSON Stores)                │
├──────────────────────────┬──────────────────────────────┤
│  RuleCollections.json    │    CustomRules.json          │
│  (collection states)     │    (user-defined rules)      │
└────────────┬─────────────┴──────────────┬───────────────┘
             │                            │
             └──────────┬─────────────────┘
                        │ ONE-WAY GENERATION
                        ▼
┌─────────────────────────────────────────────────────────┐
│              keypath.kbd (Generated Output)             │
├─────────────────────────────────────────────────────────┤
│  ;; === KEYPATH MANAGED ===                             │
│  (defsrc ...) (deflayer base ...)                       │
│                                                         │
│  ;; === USER SECTION (preserved) ===                    │
│  (defalias my-advanced-stuff ...)                       │
└─────────────────────────────────────────────────────────┘
```

## Key Invariants

### 1. Save Order Matters

```swift
// Config validates and writes FIRST
try await configurationService.saveConfiguration(ruleCollections, customRules)
// Only then persist to stores (atomic success)
try await ruleCollectionStore.saveCollections(ruleCollections)
try await customRulesStore.saveRules(customRules)
```

This prevents store/config mismatch if validation fails.

### 2. Segmented Ownership

KeyPath only modifies its managed sections (sentinel blocks like `KP:BEGIN`/`KP:END`). User additions outside these blocks are preserved.

### 3. Single Write Path

ALL config writes go through `RuleCollectionsManager.regenerateConfigFromCollections()`. No direct writes to config file from other components.

## External Config Edits

- File watcher detects changes but does NOT sync back to JSON stores
- Manual edits in user section are preserved
- Manual edits in KeyPath-managed section will be overwritten on next save

## Runtime State

Via TCP, not config parsing:
- Layer names: `layer-names` command
- Active layer: `current-layer` command
- Key mappings: kanata-simulator with layer held

## Related
- [ADR-023: No Config Parsing](adr-023-no-config-parsing.md)
