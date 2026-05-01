# Multi-App Conditions for Rules

**Status:** Proposed (not yet implemented)
**Author:** TBD
**Created:** 2026-04-28

## Summary

Allow a single key-mapping rule to apply to **multiple apps** instead of just one. Today the inspector and overlay support "Any App" or "Only in *one* app". This proposal extends "Only in..." to accept a set of apps, e.g. *Only in Safari, Chrome, Arc*.

## Motivation

Users frequently want the same rule across a small group of related apps:

- Same browser shortcut across Safari, Chrome, Arc, Firefox.
- Same vim-style nav layer across all JetBrains IDEs.
- Same media-key remap across Spotify, Music, YouTube Music.

Today they must duplicate the rule per app (creating N near-identical entries in the App Rules tab and N override blocks in the kanata config). This is tedious to author, tedious to maintain, and clutters the rules list.

## Current Architecture (single-app)

A rule's app constraint is a single optional value that flows through several layers:

| Layer | Type / Field | File |
|---|---|---|
| In-memory model | `AppConditionInfo?` | `MapperActionTypes.swift` |
| View model | `MapperViewModel.selectedAppCondition: AppConditionInfo?` | `MapperViewModel.swift` |
| Manager | `AppConditionManager.selectedAppCondition: AppConditionInfo?` | `Mapper/AppConditionManager.swift` |
| Persisted rule | `AppKeymap` (one app per keymap) | `AppKeyMapping.swift` |
| Storage file | `~/.config/keypath/AppKeymaps.json` | `AppKeymapStore.swift` |
| Kanata config | One `defalias`/`deflayer` block per app | `AppConfigGenerator` |

UI surfaces that display or edit the constraint:

- Inspector panel — `MapperView+Inspector.swift` (Any App / Only in...)
- Overlay popover — `OverlayMapperSection.swift` + `OverlayMapperSection+AppMappingIndicators.swift`
- App-mapping indicators — small icons under the input keycap (`appMappingIndicators`)
- App Rules tab — list of per-app rule cards
- Picker sheet — `Mapper/AppConditionPickerSheet.swift`

## Proposed Design

### Data model

Replace single optional with an array (or set) of conditions:

```swift
// Was:
var selectedAppCondition: AppConditionInfo?

// New:
var selectedAppConditions: [AppConditionInfo]   // empty = Any App
```

Internally store a `Set<String>` of bundle IDs to deduplicate; resolve display name + icon lazily for rendering.

### Storage

`AppKeymaps.json` becomes a list of *rules*, each with:

```json
{
  "bundleIdentifiers": ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser"],
  "overrides": [{ "inputKey": "j", "outputAction": "down" }, ...]
}
```

- **Migration:** existing single-app entries map to a one-element `bundleIdentifiers` array. A version bump in the JSON header (`"schema": 2`) triggers the migration on first load. Old `bundleIdentifier` field continues to be read for one release for safety.
- **Identity:** rules are keyed by sorted `bundleIdentifiers + overrides` hash. Two rules with the same overrides but different app sets are distinct.

### Kanata config generation

For each rule, expand to per-app blocks during generation. The kanata side stays single-app — KeyPath just emits N copies internally:

```
;; Rule: j→down in [Safari, Chrome]
(deflayer safari ... j down ...)
(deflayer chrome ... j down ...)
```

This keeps the kanata fork unchanged and avoids new runtime mechanics. The user-visible saving is purely in the editing experience and the on-disk JSON.

### UI changes

**Picker sheet** (`AppConditionPickerSheet.swift`):
- Each app row gets a checkmark instead of being a single-tap selector.
- Header shows count: "Choose Apps (3 selected)".
- "Done" button replaces auto-dismiss-on-select.
- Browse... still works; appends the chosen app to the set.

**Inspector "Only in..." row:**
- Single app: "Only in Safari" + app icon (current behavior).
- Multiple apps: "Only in Safari +2" with stacked/overlapping icons (Safari icon foreground, others peeking).
- Tap to re-open the picker sheet pre-populated with current selection.

**Overlay popover "Only in..." option:**
- Same compact treatment as the inspector ("Only in Safari +2" with stacked icons).

**App-mapping indicators** (small icons under the keycap):
- Show one icon *per app the rule targets*. A rule on three apps shows three icons (current behavior already iterates `appsWithCurrentKeyMapping`, so this mostly works for free if we expand the rule into the in-memory `[AppKeymap]` per app for display purposes).

**App Rules tab:**
- A rule that targets multiple apps shows a single card with a stacked-icon header instead of N near-identical cards.
- Clicking the card opens the editor with all apps selected.

### Display strings

Standardize a single helper, e.g. `AppConditionInfo.displayLabel(for: [AppConditionInfo]) -> String`:

| Count | Format |
|---|---|
| 0 | "Any App" |
| 1 | "Only in Safari" |
| 2 | "Only in Safari & Chrome" |
| 3+ | "Only in Safari +2" (tooltip lists all) |

Use this everywhere — inspector, overlay, rule card, accessibility label.

## Open Questions

1. **Per-app overrides within a rule.** Do we want to allow the *same* rule to behave slightly differently per app (e.g. `j→down` in Safari but `j→pgdn` in Chrome)? This proposal says **no** — if the outputs differ, it's two rules. Keeps the model simple.
2. **Bundle-ID groups.** Should we ship pre-canned groups (Browsers, JetBrains, Office)? Could be a follow-up; the multi-select sheet should work first.
3. **Negative conditions.** "All apps *except* X" is a related ask but out of scope here — would need a separate `excludedBundleIdentifiers` field.
4. **Wildcards.** `com.jetbrains.*` would cover all JetBrains IDEs in one entry. Out of scope; revisit after groups land.

## Migration & Rollout

1. Land schema v2 with read-old-write-new behavior.
2. One release later, drop the legacy single-`bundleIdentifier` reader.
3. No user-facing migration UI required — the JSON migration is silent on first load.

## Effort Estimate

- Data model + storage migration: ~half day
- Kanata config generator expansion: ~couple hours (mostly a loop)
- Picker sheet multi-select: ~half day
- Display labels + icon stacks across 4 surfaces: ~day
- Tests (storage roundtrip, config generation, label formatting): ~half day

Total: ~2–3 dev days.

## Non-Goals

- No changes to the kanata fork.
- No changes to the per-app TCC / accessibility flow.
- No new "rule groups" abstraction in the UI — just multi-app per rule.
