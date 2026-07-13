# Vallack System Pack — Implementation Plan

## Context

We researched Ben Vallack's keyboard system (#340) and want to build a "Vallack System" pack that users can toggle on/off as a unit. The system bundles two interdependent pieces: a **two-row modifier split** (OS mods on top row, layer toggles on home row) and a **nav layer** (arrows, clipboard, tab switching, Home/End).

This is the first "system pack" — a pack that coordinates multiple mechanisms (RuleCollection + HomeRowModsConfig + HomeRowLayerTogglesConfig) behind a single toggle. It uses the existing `Pack` model's `associatedCollectionID` and install/uninstall flow, extended to apply config presets atomically.

Related issues: #340 (research), #374 (system pack spec), #375 (conflict detection), #376 (system packs vision).

## Scope

- All-or-nothing toggle (no per-component toggles)
- Two components: two-row mod split + nav layer
- Action catalog expansion (prerequisite)

## Progress

- [x] Step 1: Expand action catalog (23 → 40 actions)
- [x] Step 2: Add Vallack nav layer RuleCollection
- [x] Step 3: Add two-row mod split presets
- [x] Step 4: Register pack in PackRegistry
- [x] Step 5: Extend PackInstaller for system-level config changes

## Step 1: Expand SystemActionInfo.allActions ✅

**File:** `Sources/KeyPathAppKit/UI/Mapper/MapperActionTypes.swift`

Added 17 new actions:
- Cursor movement: Word Left/Right (`A-left`/`A-right`), Line Start/End (`home`/`end`)
- Deletion: Delete Word (`A-bspc`), Kill Line (`C-k`)
- Selection: Select Word Left/Right, Select to Line Start/End
- Tab/Window: Previous/Next Tab, App Switcher, Window Switcher, Close Tab
- System: Screenshot (`C-M-S-4`), Forward Delete (`del`)

**File:** `Sources/KeyPathAppKit/UI/Components/OutputActionTypes.swift`

Reorganized output picker from 5 groups to 9: Clipboard, Cursor Movement, Selection, Deletion, Tab/Window, System, Playback, Volume, Display.

**Tests:** Updated count assertions in `SystemActionInfoTests.swift` (23 → 40 total, 8 → 11 media/HID, 8 → 22 editing).

## Step 2: Add Vallack Nav Layer as a RuleCollection

**File:** `Sources/KeyPathAppKit/Services/RuleCollections/RuleCollectionCatalog.swift`

Add a new builder method that returns a `RuleCollection` with:
- Stable UUID in `RuleCollectionIdentifier` (file: `RuleCollectionModels.swift`)
- `name`: "Vallack Navigation"
- `category`: `.navigation`
- `targetLayer`: New layer activated by momentary activator
- `momentaryActivator`: Mirrored — hold left index (F) or right index (J)
- `configuration`: `.list`
- Disabled by default (the Pack toggle controls it)

Key mappings (adapted from Vallack's Kanata `cmd` layer to QWERTY positions):

```
Right hand (navigation)          Left hand (switching/editing)
─────────────────────           ─────────────────────────────
H → Left                        Q → Tab
J → Down                        W → Esc
K → Up                          E → Prev Tab (C-S-tab)
L → Right                       R → Next Tab (C-tab)
U → Backspace                   A → Cmd+Tab (app switcher)
I → Enter                       S → Home (line start)
Y → Copy (M-c)                  D → End (line end)
; → Paste (M-v)                 G → Screenshot (C-M-S-4)
                                T → Cmd+[ (browser back)
                                V → Cmd+] (browser forward)
```

Design note: Vallack's layout is for Graphite, so we adapt the concept (right hand = arrows + editing, left hand = switching + clipboard) to QWERTY physical positions. The principle is the same: hold an index finger, everything you need is under the other hand.

## Step 3: Add HomeRowModsConfig Preset for Two-Row Split

**File:** `Sources/KeyPathAppKit/Models/HomeRowModsConfig.swift`

Add static preset `vallackTwoRowSplit` alongside `cagsMacDefault` and `gacsWindows`:

Top row keys (Q-row) get OS modifiers:
- Left: Q→Ctrl, W→Alt, E→Cmd (pinkies get 300ms, others 200ms)
- Right: O→Ctrl, I→Alt, U→Cmd

This frees the home row for layer toggles.

**File:** `Sources/KeyPathAppKit/Models/HomeRowLayerTogglesConfig.swift`

Add preset with nav layer toggles on home-row index fingers:
- F-hold → nav layer (left hand activator)
- J-hold → nav layer (right hand activator, mirrored)

Uses `layer-while-held` mode so the layer deactivates on release.

## Step 4: Register the Vallack System Pack

**File:** `Sources/KeyPathAppKit/Services/Packs/PackRegistry.swift`

```swift
public static let vallackSystem = Pack(
    id: "com.keypath.pack.vallack-system",
    version: "1.0",
    name: "Vallack System",
    tagline: "Your fingers stay put, the keyboard changes",
    shortDescription: "...",
    longDescription: "...",
    category: "System",
    iconSymbol: "rectangle.stack.badge.play",
    bindings: [],
    associatedCollectionID: RuleCollectionIdentifier.vallackNavigation
)
```

Add to `starterKit` array.

The Pack uses `associatedCollectionID` to toggle the nav layer RuleCollection. The two-row mod config is applied as part of the install flow (Step 5).

## Step 5: Extend PackInstaller for System-Level Config Changes

**File:** `Sources/KeyPathAppKit/Services/Packs/PackInstaller.swift`

When installing `vallackSystem`:
1. Toggle the associated nav layer RuleCollection (existing flow via `associatedCollectionID`)
2. Snapshot current HomeRowModsConfig and HomeRowLayerTogglesConfig
3. Apply `vallackTwoRowSplit` HomeRowModsConfig preset
4. Apply the nav layer toggle HomeRowLayerTogglesConfig preset

When uninstalling:
1. Toggle off the nav layer RuleCollection
2. Revert HomeRowModsConfig to snapshot
3. Revert HomeRowLayerTogglesConfig to snapshot

This follows the same snapshot/rollback pattern already used by the collection toggle mechanism in `RuleCollectionsManager+PublicAPI.swift`.

## Files to Modify

| File | Change | Status |
|------|--------|--------|
| `MapperActionTypes.swift` | Add 17 new actions | ✅ Done |
| `OutputActionTypes.swift` | Reorganize into 9 groups | ✅ Done |
| `SystemActionInfoTests.swift` | Update count assertions | ✅ Done |
| `RuleCollectionCatalog.swift` | Add `vallackNavigation` collection | ✅ Done |
| `RuleCollectionModels.swift` | Add UUID to `RuleCollectionIdentifier` | ✅ Done |
| `HomeRowModsConfig.swift` | Add `vallackTwoRowSplit` preset | ✅ Done |
| `HomeRowLayerTogglesConfig.swift` | Add Vallack layer toggle preset | ✅ Done |
| `PackRegistry.swift` | Add `vallackSystem` pack | ✅ Done |
| `PackInstaller.swift` | Handle system-level config on install/uninstall | ✅ Done |
| `OutputActionGroupingTests.swift` | Fix tests for 9-group structure | ✅ Done |

## Verification

1. `swift build` — no compiler errors
2. `swift test` — all pass
3. Open overlay mapper → output picker shows 9 groups with new actions
4. Gallery shows Vallack System pack with philosophy description
5. Toggle on → nav layer activates, home row mods switch to two-row split
6. Hold F or J → arrows, clipboard, tab switching all work on the nav layer
7. Toggle off → everything reverts to previous state
8. Undo snapshot works for the multi-config change
