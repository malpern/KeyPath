# Unified Mapping Model

## Problem

KeyPath has four separate models that all represent the same concept — "when this key is pressed, do this thing":

| Model | Purpose | Output type | Persistence |
|-------|---------|-------------|-------------|
| `CustomRule` | User-authored mappings from the mapper | Key name (string) | CustomRules.json |
| `KeyMapping` | Built-in collection mappings | Key name (string) | RuleCollections.json (inside RuleCollection) |
| `LauncherMapping` | Quick Launcher shortcuts | `LauncherTarget` enum (app/url/folder/script) | RuleCollections.json (inside LauncherGridConfig) |
| `AppKeyOverride` | App-specific key overrides | Kanata action string | AppKeymaps.json |

These models share the same core shape (input key → output action) but diverge in:
- How they represent the output (string vs enum vs raw kanata)
- What metadata they carry (behavior, description, icon, device overrides)
- Where they're stored (three different JSON files, three different store classes)
- How they feed into the config generator (three different code paths)

**Consequences:**
- Features added to one model aren't available in others (scripts only in launcher, tap-hold only in custom rules, app conditions only in app overrides)
- UI duplication — the mapper and launcher have separate editors for the same concept
- New output types (scripts, folders) require plumbing through each model separately
- The translation layer between models (recently removed QuickLaunchMapping ↔ LauncherMapping) was a symptom of this fragmentation

## Current Architecture

### Models

**CustomRule** — The richest model. Has:
- input/output (strings)
- shiftedOutput (shift variant)
- behavior (tap-hold, tap-dance, macro, chord)
- targetLayer (base, nav, custom)
- deviceOverrides (per-keyboard outputs)
- packSource (which pack installed it)
- isEnabled, title, notes, createdAt

**KeyMapping** — The config generator's internal unit. Has:
- input/output (strings)
- shiftedOutput, ctrlOutput
- behavior (same MappingBehavior as CustomRule)
- deviceOverrides
- description, sectionBreak (display hints)

**LauncherMapping** — Output is a typed enum, not a string. Has:
- key (input)
- target: LauncherTarget (.app, .url, .folder, .script)
- customIconPath, userDescription
- isEnabled

**AppKeyOverride** — Minimal. Has:
- inputKey, outputAction (raw kanata string)
- description
- App context (via parent AppKeymap.bundleIdentifier)

### Persistence

```
~/.config/keypath/
├── CustomRules.json        → [CustomRule]
├── RuleCollections.json    → [RuleCollection] (contains [KeyMapping] + LauncherGridConfig)
└── AppKeymaps.json         → [AppKeymap] (contains [AppKeyOverride])
```

Three store classes: `CustomRulesStore`, `RuleCollectionStore`, `AppKeymapStore`

### Config Generation

All models ultimately produce kanata syntax through different paths:
- CustomRule → `.asKeyMapping()` → fed into RuleCollectionsManager → KanataConfiguration
- KeyMapping → directly inside RuleCollection.mappings → KanataConfiguration
- LauncherMapping → `.target.kanataOutput` produces `(push-msg "...")` → wrapped in KeyMapping → KanataConfiguration
- AppKeyOverride → separate `keypath-apps.kbd` file with virtual keys and switch expressions

## Proposed Unified Model

### Core: `KeyAction`

A single type for "what happens when you press a key":

```swift
enum KeyAction: Codable, Equatable, Sendable {
    /// Emit a different key
    case keystroke(key: String, shiftedKey: String?)
    
    /// Launch an application
    case launchApp(name: String, bundleId: String?)
    
    /// Open a URL
    case openURL(String)
    
    /// Open a folder in Finder
    case openFolder(path: String, name: String?)
    
    /// Run a script
    case runScript(path: String, name: String?)
    
    /// Trigger a system action (Mission Control, volume, etc.)
    case systemAction(id: String)
    
    /// Switch to a layer
    case activateLayer(name: String)
    
    /// Raw kanata expression (escape hatch for power users)
    case rawKanata(String)
}
```

### Core: `KeyRule`

A single model for all input → output mappings:

```swift
struct KeyRule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var input: String                          // The physical key
    var action: KeyAction                      // What happens on tap
    var behavior: MappingBehavior?             // Tap-hold, tap-dance, etc.
    var isEnabled: Bool
    
    // Conditions (when does this rule apply?)
    var targetLayer: RuleCollectionLayer       // Which layer (.base, .nav, .custom)
    var appCondition: String?                  // Bundle ID (nil = all apps)
    var deviceCondition: String?               // Device hash (nil = all keyboards)
    
    // Metadata
    var title: String?
    var description: String?
    var customIconPath: String?
    var source: RuleSource                     // .user, .pack(id), .system
    var createdAt: Date
}

enum RuleSource: Codable, Equatable, Sendable {
    case user
    case pack(String)
    case system
}
```

### What this unifies

| Current | Becomes |
|---------|---------|
| `CustomRule(input: "caps", output: "esc")` | `KeyRule(input: "caps", action: .keystroke(key: "esc"))` |
| `LauncherMapping(key: "a", target: .app(name: "Calendar"))` | `KeyRule(input: "a", action: .launchApp(name: "Calendar"), targetLayer: .custom("launcher"))` |
| `AppKeyOverride(inputKey: "j", outputAction: "down")` | `KeyRule(input: "j", action: .keystroke(key: "down"), appCondition: "com.apple.Safari")` |
| `KeyMapping(input: "h", output: "left")` | `KeyRule(input: "h", action: .keystroke(key: "left"), targetLayer: .navigation)` |

### What this enables

- **Any output type on any key.** The mapper can assign scripts, the launcher can use tap-hold, app-specific rules can launch apps.
- **One editor for everything.** Input key + output action picker + behavior (optional) + conditions (optional). Same UI everywhere.
- **One persistence path.** All rules in one store, one file.
- **One config generation path.** `KeyAction.kanataOutput` produces the right kanata syntax for any action type.

## Pros and Cons

### Pros

- **Eliminates model duplication.** One type instead of four.
- **Feature parity by default.** Scripts, tap-hold, app conditions, device overrides — available everywhere without per-model plumbing.
- **Simpler config generator.** One code path from KeyRule → kanata syntax.
- **Simpler persistence.** One store, one file, one migration path.
- **Enables new features.** "Hold Caps Lock for Hyper, tap for app launch" — currently impossible because CustomRule outputs strings and LauncherMapping outputs LauncherTarget. With KeyAction, this is just `behavior: .dualRole(tap: .launchApp(...), hold: .keystroke("hyper"))`.

### Cons

- **Massive migration.** Touches every UI, every store, every config generator path. Likely 2-3 weeks of focused work.
- **Backward compatibility.** Existing JSON files need migration. Users on older versions would lose config on upgrade without a migrator.
- **RuleCollection complexity.** Collections group mappings with shared config (timing, activation mode). The grouping concept would need to survive — KeyRule alone doesn't capture "these 8 home row keys share a 200ms hold timeout."
- **Over-generalization risk.** Not every combination makes sense (tap-dance on a launcher shortcut?). The unified model allows nonsensical combinations that the UI would need to prevent.
- **Testing surface.** Every existing test that creates a CustomRule, KeyMapping, or LauncherMapping would need updating.

## Alternative: Shared Output Type Only

Instead of unifying the entire model, unify just the output representation:

```swift
// Replace String outputs and LauncherTarget with KeyAction
// Keep CustomRule, KeyMapping, LauncherMapping as separate structs
// But they all use KeyAction for their output

struct CustomRule {
    var input: String
    var action: KeyAction        // was: var output: String
    var behavior: MappingBehavior?
    // ... rest unchanged
}

struct LauncherMapping {
    var key: String
    var action: KeyAction        // was: var target: LauncherTarget
    var customIconPath: String?
    // ... rest unchanged
}
```

**Pros:** Much smaller change. Each model keeps its identity. Config generator gets a shared `KeyAction.kanataOutput` method. New output types (scripts) work everywhere.

**Cons:** Still three models, three stores, three persistence files. Doesn't solve the "one editor" or "one persistence path" goals. Incremental improvement, not a structural fix.

## Phasing

### Phase 0: Shared Output Type (2-3 days)
- Create `KeyAction` enum
- Add `KeyAction` to `CustomRule` and `KeyMapping` (alongside existing `output: String` for backward compat)
- Config generator uses `KeyAction.kanataOutput` when present, falls back to string
- No UI changes, no persistence changes
- **Value:** Scripts and app launches become available in the mapper without UI work

### Phase 1: Unified Persistence (1 week)
- Create `KeyRuleStore` that stores `[KeyRule]`
- Migrate CustomRules.json → KeyRules.json on first launch
- LauncherMapping → KeyRule with targetLayer = launcher
- AppKeyOverride → KeyRule with appCondition
- Keep old stores as read-only for migration
- **Value:** One file, one store, one source of truth

### Phase 2: Unified Editor (1 week)
- Build `KeyRuleEditor` that replaces LauncherMappingEditor and the mapper's output recording
- Input picker + output type picker (keystroke/app/url/script/system) + behavior (tap-hold/etc) + conditions (app/device/layer)
- Both overlay and gallery use the same editor
- **Value:** Feature parity everywhere, one editor to maintain

### Phase 3: Unified Config Generation (3-5 days)
- Replace per-model config generator methods with single `KeyRule → kanata` path
- Remove `CustomRule.asKeyMapping()` translation
- Remove `LauncherTarget.kanataOutput` (replaced by `KeyAction.kanataOutput`)
- **Value:** Simpler config generator, fewer code paths to test

### Phase 4: Remove Legacy Models (2-3 days)
- Delete `CustomRule`, `QuickLaunchMapping` (already done), `AppKeyOverride`
- Delete old store classes
- Delete migration code after one release cycle
- **Value:** Clean codebase, no dead code

**Total:** ~4-5 weeks for full unification. Phase 0 alone delivers immediate value (scripts in mapper) in 2-3 days.

## Recommendation

Start with **Phase 0** (shared output type). It's low-risk, backward-compatible, and immediately enables scripts/app launches in the mapper. Evaluate whether the full unification is worth it after Phase 0 ships and we see how `KeyAction` feels in practice.

The full unification (Phases 1-4) is the right long-term architecture, but it's a big investment that should be planned as a dedicated milestone, not bolted on incrementally.

## Open Questions

1. **RuleCollection grouping.** Collections group related rules with shared config (timing, activation mode, category). How does this work with a flat `[KeyRule]` store? Options: (a) KeyRule has a `collectionId` field, (b) collections reference rules by ID, (c) collections are just metadata attached to a filter/query.

2. **Pack installation.** Packs currently create CustomRules. With KeyRule, packs would create KeyRules with `source: .pack(packId)`. Uninstalling a pack deletes rules with that source. Same semantics, different model.

3. **App-specific config file.** AppKeyOverrides generate a separate `keypath-apps.kbd` file loaded by kanata at runtime. Would KeyRules with `appCondition` still generate a separate file, or would they be inlined into the main config?

4. **Performance.** One big `[KeyRule]` array instead of three smaller arrays. Probably fine for hundreds of rules, but worth profiling if we reach thousands (community rules scenario).
