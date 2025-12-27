# ADR-023: No Config File Parsing - Use TCP and Simulator

**Status:** Accepted
**Date:** 2024

## Context

KeyPath needs to understand Kanata configuration (layer names, key mappings) for the overlay UI.

## Decision

KeyPath must **NEVER** parse Kanata config files directly. All config understanding comes from Kanata itself.

## Implementation

| Need | Solution |
|------|----------|
| Layer names and state | TCP `layer-names` and `current-layer` commands |
| Key mappings per layer | kanata-simulator with layer-switch key held |
| Config validation | Let Kanata validate, report errors via TCP |

## Why Not Parse Configs?

1. **Kanata is the source of truth** - Parsing would create a shadow implementation that can drift
2. **Config syntax is complex** - Aliases, macros, tap-hold, forks, layer-switch, includes, variables
3. **Maintenance burden** - Every Kanata syntax change would require KeyPath updates
4. **Already solved** - Simulator handles all edge cases correctly

## What's Allowed

| Action | Allowed? |
|--------|----------|
| Reading config file path to pass to simulator | ✅ |
| Checking if config file exists | ✅ |
| Computing file hash for cache invalidation | ✅ |
| Regex/parsing to extract layer names | ❌ |
| Interpreting Kanata syntax (defsrc, deflayer, etc.) | ❌ |
| Building data structures from config text | ❌ |

## Implementation Approach

- TCP for runtime state (current layer, layer list)
- Simulator for static analysis (what does key X output in layer Y?)
- If simulator lacks a feature, extend it in our local Kanata fork (`External/kanata`)

## Related
- [ADR-025: Configuration Management](adr-025-config-management.md)
