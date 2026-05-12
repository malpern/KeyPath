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

### Phase 0: Shared Output Type ✅ DONE
- Created `KeyAction` enum with 8 cases: `keystroke`, `launchApp`, `openURL`, `openFolder`, `runScript`, `systemAction`, `activateLayer`, `rawKanata`
- Replaced `output: String` on `CustomRule`, `KeyMapping`, and `AppKeyOverride` with `action: KeyAction`
- Replaced `LauncherMapping.target: LauncherTarget` with `LauncherMapping.action: KeyAction`
- Deleted `LauncherTarget` enum (fully subsumed by `KeyAction`)
- Updated config generators, all UI, services, and tests (112 files, 413 tests pass)
- **What it enables:** The type system now supports any output type on any model. A `CustomRule` can hold `.runScript(...)` or `.launchApp(...)`, not just keystroke strings.

### Phase 1: Unified Persistence (1 week)
- Create `KeyRuleStore` that stores `[KeyRule]`
- Migrate CustomRules.json → KeyRules.json on first launch
- LauncherMapping → KeyRule with targetLayer = launcher
- AppKeyOverride → KeyRule with appCondition
- Keep old stores as read-only for migration
- **Value:** One file, one store, one source of truth

### Phase 2: Unified Editor (1-2 weeks)

The mapper and launcher currently have separate editors that each support a subset of `KeyAction` cases. This phase creates a single output editor that works everywhere.

#### Current State

**Mapper** (`MapperViewModel` + `MapperView`):
- Output captured via key recording (`RecordingCoordinator` → `KeyboardCapture`)
- Auto-detect output type in `finalizeCapture()`: checks `selectedApp`, `selectedURL`, `selectedSystemAction`, then falls back to keystroke
- Supports: keystroke, app launch, URL, system action
- Missing: folder, script, layer switch
- Has advanced behaviors (tap-hold, tap-dance, macro, chord) but only for keystroke outputs

**Launcher** (`LauncherMappingEditor` in `LauncherCollectionView.swift`):
- Form-based editor with `TargetType` segmented picker (app/website/folder/script)
- Each type shows a specialized form: file browser for apps, text field for URLs, etc.
- Supports: app launch, URL, folder, script
- Missing: keystroke, system action, layer switch, advanced behaviors

**App-specific** (`MapperViewModel+AppKeymapIntegration.swift`):
- Reuses mapper recording flow, scoped to an app via `selectedAppCondition`
- Creates `AppKeyOverride` with the recorded output
- Missing: all non-keystroke output types (can't assign "launch app X when in Safari")

#### Goal

One output picker component that:
1. Lets the user choose an output type (keystroke, app, URL, folder, script, system action, layer)
2. Shows the right sub-editor for each type (key recording, file browser, text field, picker)
3. Returns a `KeyAction` to the caller
4. Works in the overlay mapper, the gallery launcher editor, and app-specific rules

#### Architecture: `KeyActionPicker`

```swift
struct KeyActionPicker: View {
    @Binding var action: KeyAction
    var allowedTypes: Set<KeyActionType>  // constrain which types appear
    var onSave: (KeyAction) -> Void
    
    enum KeyActionType: CaseIterable {
        case keystroke, app, url, folder, script, systemAction, layer
    }
}
```

**Sub-editors by type:**

| Type | UI Component | Data Source |
|------|-------------|-------------|
| Keystroke | Key recording (existing `RecordingCoordinator`) | Keyboard capture |
| App | "Browse..." button → `NSOpenPanel` for `.app` bundles | File system |
| URL | Text field with domain validation | User input |
| Folder | "Browse..." button → `NSOpenPanel` for directories | File system |
| Script | "Browse..." button → `NSOpenPanel` for any file | File system + security gate |
| System Action | Picker/menu from `SystemActionInfo.allActions` | Built-in catalog |
| Layer | Picker from active layer names | `RuleCollectionsManager` |

**File sources to extract from:**
- App browse: `LauncherCollectionView.swift` → `browseForApp()` (~line 777)
- Folder browse: `LauncherCollectionView.swift` → `browseForFolder()` 
- Script browse: `LauncherCollectionView.swift` → `browseForScript()`
- URL field: `LauncherCollectionView.swift` → URL text field in editor
- System action picker: `OverlayMapperSection+SystemActionGroups.swift`
- Key recording: `RecordingCoordinator.swift` (stays as-is, just wired to keystroke type)

#### Mapper Changes

The mapper currently auto-detects output type via side-state (`selectedApp`, `selectedURL`, `selectedSystemAction`). With `KeyActionPicker`, this simplifies:

1. **Replace side-state with `KeyAction`:** Remove `selectedApp`, `selectedURL`, `selectedSystemAction` properties from `MapperViewModel`. Replace with a single `pendingAction: KeyAction?` that the picker sets directly.

2. **Output keycap becomes a type-aware display:**
   ```
   Current:  [esc] (always shows a key name)
   Unified:  [Safari ▸] or [github.com ▸] or [esc] (shows action type icon + label)
   ```

3. **Click on output keycap opens `KeyActionPicker`** instead of starting key recording. For keystroke type, the picker itself starts recording. For other types, it shows the appropriate sub-editor.

4. **`finalizeCapture()` simplifies:** No more type detection. The `KeyActionPicker` already returns the correct `KeyAction` case. `save()` just stores it.

5. **`MapperViewModel+LayerManagement.swift` simplifies:** The separate `saveAppLaunchMapping()`, `saveSystemActionMapping()`, `saveURLMapping()` methods collapse into one `save()` that stores whatever `KeyAction` the picker returned.

**Files to modify:**

| File | Change |
|------|--------|
| `MapperViewModel.swift` | Remove `selectedApp/URL/SystemAction`, add `pendingAction: KeyAction?` |
| `MapperViewModel+ConflictResolution.swift` | Simplify `finalizeCapture()` — no type detection |
| `MapperViewModel+LayerManagement.swift` | Collapse 4 save methods into 1 |
| `MapperView.swift` | Output keycap displays `KeyAction.displayName` with type icon |
| `OverlayMapperSection.swift` | Wire output area to `KeyActionPicker` |
| `RecordingCoordinator.swift` | No change — still used for keystroke sub-editor |

#### Launcher Changes

Replace `LauncherMappingEditor` (the modal form in `LauncherCollectionView.swift`) with a wrapper around `KeyActionPicker`:

1. **`LauncherMappingEditor` becomes thin:** Key selector + `KeyActionPicker` + icon/description fields. No more `TargetType` enum or per-type form sections.

2. **Add keystroke support to launcher:** Users can now assign a key remap on the launcher layer, not just app/URL/folder/script. The `KeyActionPicker`'s keystroke sub-editor (key recording) handles this.

3. **Add system action support to launcher:** Mission Control, volume, brightness controls assignable from the launcher keyboard.

**Files to modify:**

| File | Change |
|------|--------|
| `LauncherCollectionView.swift` | Replace `LauncherMappingEditor` body with `KeyActionPicker` + metadata fields |
| `LauncherDrawerView.swift` | Update type display to use `KeyAction` type icons |
| `LauncherKeycapView.swift` | Already uses `KeyAction` — may need new icons for keystroke/system types |

#### App-Specific Rule Changes

`saveAppSpecificMapping()` currently only handles keystroke outputs. With `KeyActionPicker` in the mapper, it naturally gets all output types:

1. User selects an app condition in the mapper
2. User picks any output type via `KeyActionPicker`
3. `save()` creates an `AppKeyOverride` with the chosen `KeyAction`
4. Config generator already handles `action.kanataOutput` for all types

No additional files need changing — the mapper changes cascade.

#### Behavior Compatibility

Not all `KeyAction` types make sense with all behaviors:

| Behavior | keystroke | app/url/folder/script | systemAction | layer |
|----------|-----------|----------------------|-------------|-------|
| Simple remap | ✅ | ✅ | ✅ | ✅ |
| Tap-hold | ✅ tap + hold | ✅ tap + hold | ✅ | ✅ |
| Tap-dance | ✅ | ⚠️ unusual | ⚠️ | ❌ |
| Macro | ✅ | ❌ | ❌ | ❌ |
| Chord | ✅ | ✅ | ✅ | ❌ |

`KeyActionPicker` should show/hide the behavior section based on the selected action type. Tap-hold is the most useful combo: "tap for Escape, hold to launch Terminal."

#### Migration Path

- `LauncherMappingEditor` stays as a thin wrapper initially — it calls `KeyActionPicker` for the output selection but keeps its own key/icon/description fields
- Mapper gains an "output type" selector that defaults to keystroke (preserving current UX for simple remaps)
- No persistence changes — both mapper and launcher already save `KeyAction`
- Gradual: ship keystroke-only `KeyActionPicker` first, add file-browser types one at a time

#### Value

- **Feature parity:** Scripts in the mapper, key remaps in the launcher, app launches in app-specific rules
- **One editor to maintain:** Bug fixes and new output types appear everywhere
- **Tap-hold app launch:** "Hold Caps Lock for Hyper, tap to launch Terminal" — the #1 requested combo, currently impossible

### Phase 3: Unified Config Generation (3-5 days)
- Replace per-model config generator methods with single `KeyRule → kanata` path
- Remove `CustomRule.asKeyMapping()` translation
- `KeyAction.kanataOutput` already handles all output types (done in Phase 0)
- **Value:** Simpler config generator, fewer code paths to test

### Phase 4: Remove Legacy Models (2-3 days)
- Delete `CustomRule`, `QuickLaunchMapping` (already done), `AppKeyOverride`
- Delete old store classes
- Delete migration code after one release cycle
- **Value:** Clean codebase, no dead code

**Total:** ~4-5 weeks for full unification. Phase 0 is done. Phase 2 delivers the most user-visible value.

## Recommendation

Phase 0 is shipped. The next highest-impact phase is **Phase 2 (unified editor)** — it's the one that puts new capabilities in users' hands. Phase 1 (unified persistence) is important but invisible to users; it can come before or after Phase 2.

Suggested order: **Phase 0** ✅ → **Phase 2** (editor) → **Phase 1** (persistence) → **Phase 3** (config gen) → **Phase 4** (cleanup).

## Open Questions

1. **RuleCollection grouping.** Collections group related rules with shared config (timing, activation mode, category). How does this work with a flat `[KeyRule]` store? Options: (a) KeyRule has a `collectionId` field, (b) collections reference rules by ID, (c) collections are just metadata attached to a filter/query.

2. **Pack installation.** Packs currently create CustomRules. With KeyRule, packs would create KeyRules with `source: .pack(packId)`. Uninstalling a pack deletes rules with that source. Same semantics, different model.

3. **App-specific config file.** AppKeyOverrides generate a separate `keypath-apps.kbd` file loaded by kanata at runtime. Would KeyRules with `appCondition` still generate a separate file, or would they be inlined into the main config?

4. **Performance.** One big `[KeyRule]` array instead of three smaller arrays. Probably fine for hundreds of rules, but worth profiling if we reach thousands (community rules scenario).
