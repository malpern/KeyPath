# Feature Parity Across Configuration Surfaces

## Status: Proposal — not yet started

## Context

With the action model unification complete (#346), every configuration surface shares the same `KeyAction` enum for outputs and `MappingBehavior` enum for advanced key mechanics. The data layer is uniform. But the UI surfaces have different capabilities — some can configure behaviors that others can't. This document proposes closing those gaps while preserving each surface's unique interaction model.

## Current State

### What each surface can do today

| Capability | Mapper | Rules Tab | Packs | App Keymaps |
|------------|--------|-----------|-------|-------------|
| Simple remap | yes | yes | yes | yes |
| Tap-hold | yes | yes | template only | **no** |
| Tap-dance | yes | yes | no | **no** |
| Macro | yes | yes | no | **no** |
| Chord | yes | yes | no | **no** |
| App launch / URL / script | yes | yes | no | yes |
| System actions | yes | yes | no | yes |
| Window actions | yes | yes | no | yes |
| Device conditioning | yes | yes | no | no |
| Shifted output (fork) | yes | yes | no | no |
| Layers | yes | yes | yes | no |

### What the data model supports

`KeyAction`: keystroke, hyper, meh, launchApp, openURL, openFolder, runScript, systemAction, notify, windowAction, fakeKey, activateLayer, rawKanata

`MappingBehavior`: dualRole (tap-hold), tapOrTapDance, macro, chord

Every model struct that holds a `KeyAction` can theoretically also hold a `MappingBehavior?`. The data layer imposes no limits — the gaps are purely in UI.

## The Biggest Gap: App Keymaps

`AppKeyOverride` has `action: KeyAction` but no `behavior: MappingBehavior?` field. Users can remap keys per-app, but can't attach advanced behaviors. This means:

- "In Safari, CapsLock taps Esc, holds Ctrl" — **can't do**
- "In VS Code, Semicolon taps Semicolon, holds to activate nav layer" — **can't do**
- "In Terminal, key combo triggers a macro" — **can't do**

These are natural per-app customizations that the mapper already supports globally.

### Model change required

```swift
// Current
public struct AppKeyOverride: Codable, Equatable, Sendable {
    public let inputKey: String
    public let action: KeyAction
    public let description: String?
}

// Proposed
public struct AppKeyOverride: Codable, Equatable, Sendable {
    public let inputKey: String
    public let action: KeyAction
    public let behavior: MappingBehavior?   // new
    public let description: String?
}
```

This is backward-compatible (nil default, `decodeIfPresent`). The config generator already handles `MappingBehavior` rendering for `KeyMapping` — the same renderer can be reused for app keymap overrides.

### UI approach

Reuse `MappingBehaviorEditor` (already handles tap-hold and tap-dance) in the app keymap editing flow. Open it as a sheet or disclosure group when the user wants advanced behavior on a per-app override. Don't redesign the app keymap list — just add a "Behavior" option when editing a single override.

## Second Priority: Pack Template Expansion

Pack templates currently support tap-hold via a `holdOutput` field on `PackBindingTemplate`. Expanding this to support macros and tap-dance would let pack authors create richer presets.

### What to add

- `behavior: MappingBehavior?` on `PackBindingTemplate` (or a simplified template representation that maps to `MappingBehavior` at install time)
- Pack install logic already creates `CustomRule` objects with full model support — it just needs the template to express more

### What to skip

- Chords in packs — chord input is inherently interactive (which keys to press together), hard to template
- Device conditioning in packs — too device-specific to pre-configure

## Third Priority: MappingBehaviorEditor Completion

The behavior editor shows macros and chords as read-only. Making them editable would complete the editor, but the mapper already handles creation of macros and chords well. This is polish.

## Sequencing

```
1. App Keymaps + behaviors (biggest user-facing gap)
   - Model: add behavior field to AppKeyOverride
   - Config gen: reuse behavior renderer for app keymap blocks
   - UI: embed MappingBehaviorEditor in app keymap editing
   - Tests: round-trip, config generation, golden file

2. Pack template expansion (richer presets)
   - Model: add behavior to PackBindingTemplate
   - Install logic: map template behavior to CustomRule.behavior
   - Tests: pack install with behaviors

3. Editor polish (completeness)
   - UI: make macros and chords editable in MappingBehaviorEditor
   - Tests: editing flows
```

Steps 1 and 2 are independent and could be parallelized.

## What to skip

- **Device conditioning everywhere** — power-user feature that makes sense in the mapper's visual context but adds complexity to simpler surfaces
- **Shifted output in app keymaps** — fork-based modifier detection is niche and would require per-app fork blocks in the kanata config, adding significant generator complexity
- **Layers in app keymaps** — app-specific layers would require rethinking the layer activation model (currently global)

## Persistence: JSON Files vs Database

### Current architecture

All configuration is stored as JSON files in `~/.config/keypath/`:

| File | Contents |
|------|----------|
| `CustomRules.json` | User-created rules |
| `AppKeymaps.json` | Per-app key overrides |
| `RuleCollections.json` | Built-in + custom rule collections |
| `keypath.kbd` | Generated kanata config (output, not source of truth) |

Each store is an actor that loads the entire file into memory, modifies in-place, and rewrites atomically. No incremental updates, no cross-file transactions.

### When a database becomes worth it

The current JSON approach works well for the current scale: tens to low hundreds of rules, a handful of app keymaps, ~20 rule collections. Files are human-readable, easy to back up, and simple to debug.

A database (SwiftData, GRDB, or SQLite) becomes worth the migration cost when **any of these are true:**

1. **Per-app behaviors ship (this proposal).** App keymaps with behaviors means the number of stored objects grows multiplicatively — N apps x M keys x optional behaviors. A user with 10 app-specific configs of 20 keys each is 200 overrides. JSON full-file rewrites become wasteful; incremental updates matter.

2. **Cross-entity queries appear.** "Which rules conflict with this app keymap?" or "Which packs contributed rules to this collection?" require joining data across what are currently separate files. JSON stores can't do this without loading everything into memory and scanning.

3. **Undo/history is needed.** If users want to revert rule changes, a database with transactions and versioning is far simpler than managing JSON snapshots.

4. **Config sync across devices.** CloudKit or iCloud Documents work much better with structured databases (SwiftData has built-in CloudKit sync) than with file-level JSON synchronization, which invites merge conflicts.

### Recommendation

**Don't migrate to a database preemptively.** JSON files are working, users can inspect them, and the migration cost is real (new dependency, data migration, testing). But **do migrate before or during the app keymaps expansion** if you expect users to create many per-app configs. The inflection point is when you're storing hundreds of objects across multiple files and need to query relationships between them.

If you do migrate, **SwiftData** is the natural choice for a macOS app targeting 14+ — it's Apple-native, has CloudKit sync built in, and doesn't require a third-party dependency. GRDB is the alternative if you need more control or lower deployment targets.

### Migration approach (when the time comes)

1. Add database alongside JSON (read from DB, fall back to JSON if empty)
2. On first launch, import JSON files into database
3. Keep JSON export as a "backup/debug" option
4. Remove JSON write path after one release cycle

This avoids a flag day and gives users a version to catch problems before the old path disappears.

## Decisions to make before starting

| Decision | Options |
|----------|---------|
| App keymap behavior UI | Inline disclosure vs sheet vs navigate to detail view |
| Pack behavior format | Extend `PackBindingTemplate` vs new template type |
| Database timing | Before app keymaps, during, or defer until scale demands |
| Scope of step 1 | Just tap-hold per app, or all behaviors at once |
