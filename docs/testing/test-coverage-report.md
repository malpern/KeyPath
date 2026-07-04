# Test Coverage Report

*Last updated: 2026-05-22*

## Overview

**Total: 3,615 tests** across 302 files in 3 test targets.

| Domain | Tests | % | Assessment |
|--------|------:|:-:|:-----------|
| Services (health, TCP, import, etc.) | 708 | 19.6% | Excellent |
| Models (KeyAction, layout, behaviors) | 587 | 16.2% | Good |
| Integration (golden, round-trip, e2e) | 584 | 16.2% | Strong |
| Rule Collections | 291 | 8.0% | Good |
| UI (overlay, HUD, keyboard viz) | 285 | 7.9% | Good |
| Installation (wizard, engine, daemon) | 243 | 6.7% | Moderate |
| Kanata Config Generation | 241 | 6.7% | Good |
| CLI (commands, facades, output) | 241 | 6.7% | Good |
| Packs | 235 | 6.5% | Good |
| Snapshot Tests | 110 | 3.0% | Solid |
| Settings/Preferences | 19 | 0.5% | Thin |
| Layout Tracer | 11 | 0.3% | Minimal |

## Source Complexity vs Test Density

| Source Directory | Lines | Tests | Tests/1K Lines |
|-----------------|------:|------:|---------------:|
| CLI | 1,817 | 241 | 133 |
| Services/Packs | 2,180 | 235 | 108 |
| Services/RuleCollections | 2,982 | 291 | 98 |
| Models | 10,050 | 587 | 58 |
| Infrastructure/Config | 4,309 | 241 | 56 |
| Managers | 5,316 | 243 | 46 |
| **Services/Configuration** | **2,939** | **71** | **24** |

## What's Well Covered

### Kanata Config Generation (~250 tests)
- All mapping generators (HRM, auto-shift, chords, launcher, tap-hold pickers, layer toggles)
- Behavior rendering + parsing round-trips for every dual-role variant
- End-to-end output structure (defcfg, defsrc, deflayer, defalias)
- Balanced parentheses safety check
- Golden file regression tests
- AI-assisted config generation

### Pack System (~235 tests)
- Registry integrity, dependency graph validation
- Install rendering (renderBindings with all variations)
- Zone resolution (colors, subtitles, layer preview)
- InstalledPackTracker persistence (CRUD, corrupt recovery, Codable)
- CLI facade (resolution by ID/slug/name/substring)
- Pack ownership and mutual exclusion

### Rule Collections (~291 tests)
- Catalog defaults, unique IDs, upgrade preservation
- Conflict detection (collection vs collection, custom rules, layer isolation)
- Store persistence with resilient recovery from corruption
- Manager API (enabledMappings, makeCustomRule, getCustomRule, layer names)
- Deduplication logic and edge cases
- Custom rule validation (33 tests)

### CLI (~241 tests)
- Rule/collection/pack CRUD operations
- Karabiner import conversion
- Output snapshot regression
- Command validation and help schemas
- Facade resolution (ambiguous match handling)

### Models (~587 tests)
- KeyAction: all 13 cases, Codable, display, kanata output
- MappingBehavior: all variants (dual-role, tap-dance, macro, chord)
- CustomRule: Codable with legacy decode, display, conversions
- PhysicalLayout: 40 tests
- ChordGroups: validation and config (55 tests)

## Remaining Gaps

### High Priority

1. **ConfigurationService save pipeline** (24 tests/1K lines)
   - The `saveConfiguration` method validates, deduplicates, generates, and writes
   - Error paths, conflict rejection, and validate-before-write invariant are lightly tested
   - The rollback-on-failure path in `toggleCollection`/`saveCustomRule` has no dedicated tests

2. **TCP client robustness**
   - Connection timeout handling, retry logic, partial reads
   - Server-not-running scenarios
   - The TCP client is the reload trigger; if it breaks, config changes don't take effect

3. **Installer engine failure paths**
   - Mid-install failures, privilege escalation denial
   - Currently golden-file heavy with limited negative testing

### Medium Priority

4. **Preferences persistence**
   - Only 19 tests; no UserDefaults round-trip tests
   - No value clamping on load (port range, timeout range)
   - No migration from older preference schemas

5. **Multi-collection conflict scenarios**
   - Tests cover 2-way conflicts but not 3+ collection interactions

6. **Device exclusion in generation**
   - No tests for `(defcfg ... macos-dev-names-include ...)` block rendering

7. **Sequence/defseq preservation**
   - The generation pipeline loads preserved sequences from disk; this path has minimal testing

### Lower Priority

8. Layout Tracer (11 tests total)
9. Performance regression tests for large configs (1000+ rules)
10. Standardize Swift Testing adoption (currently 85% XCTest / 15% @Test)

## Test Infrastructure Notes

- **Base class**: `KeyPathTestCase` / `KeyPathAsyncTestCase` sets up mock PID providers to avoid `pgrep` deadlocks in parallel test runs
- **Speed target**: <5s total per CLAUDE.md; current suite runs in ~3s
- **Frameworks**: Mix of XCTest (`func test`) and Swift Testing (`@Test`); newer files use Swift Testing
- **Golden files**: `Tests/KeyPathTests/Integration/GoldenConfigs/` for config regression
- **Snapshot tests**: `Tests/KeyPathSnapshotTests/` for UI regression (separate target)
- **Test stores**: `RuleCollectionStore.testStore(at:)` and `CustomRulesStore.testStore(at:)` for sandboxed persistence testing
