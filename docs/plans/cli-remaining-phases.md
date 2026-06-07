# CLI Phases 1–2: Agent MVP + Porcelain

**Parent issue:** #347 (CLI parity)  
**Depends on:** Phase 0 (PR #356, merged 2026-05-17)  
**PR:** #359 (squash-merged 2026-05-17)  
**Status:** All phases complete (1E deferred)

### Progress

| Sub-phase | Status | Tests | Notes |
|-----------|--------|-------|-------|
| 1A. Rule CRUD | ✅ Shipped | 43 | Full --action/--behavior JSON, --dry-run, --on-conflict |
| 1B. Collection CRUD | ✅ Shipped | 7 | create/rename/delete/duplicate/reorder |
| 1C. Layer CRUD | ✅ Shipped | 7 | create/delete/rename via targetLayer |
| 1D. Service Lifecycle | ✅ Shipped | 3 | start/stop/restart/logs via launchctl |
| 1E. Keyboard/Device | ⏳ Deferred | — | Needs HID device access; hard to unit test |
| 1F. Simulate | ✅ Done | 10 | `simulate` with mock provider seam + real integration tests |
| 1G. Schemas | ✅ Shipped | 6 | rule + collection schemas with JSON examples |
| 2A. Porcelain | ✅ Shipped | 8 | start/stop/restart/logs/unmap/list shortcuts |
| 2B. Karabiner Import | ✅ Done | 13 | `import karabiner` with --collection, --profile, --dry-run; complex_mods file format |
| 2C. Export/Import | ✅ Shipped | 14 | export/import collection round-trip |
| 2D. Conflict merge | ✅ Done | 6 | --on-conflict=merge: simple+tap-hold merge, error on ambiguous |
| 2E. Help examples | ✅ Done | 5 | `help-topics examples [noun]` with 6 topic areas |
| 2F. Snapshot tests | ✅ Done | 14 | Inline snapshots for all CLI output types |
| **Total passing** | | **~196** | All tests green |

---

## Phase 1 — Agent MVP (plumbing)

The agent-facing surface: full CRUD, structured I/O, verification loop. After Phase 1, an AI agent can configure KeyPath end-to-end without the GUI.

### 1A. Rule CRUD with Full Behavior Schema

**Goal:** `keypath rule add` supports every behavior variant the GUI offers, not just simple/tap-hold.

#### Commands

```
keypath rule add <input> <output>                  # simple remap
keypath rule add <input> --action <json>           # any KeyAction variant via JSON
keypath rule add <input> --behavior <json>         # full MappingBehavior via JSON
keypath rule add <input> --tap <key> --hold <key>  # tap-hold shorthand (existing)
keypath rule remove <input>
keypath rule list [--enabled-only]
keypath rule show <input>
```

#### Action JSON input (all 13 KeyAction variants)

```json
{"keystroke": {"key": "esc"}}
{"hyper": {}}
{"meh": {}}
{"launchApp": {"name": "Safari", "bundleId": "com.apple.Safari"}}
{"openURL": "https://example.com"}
{"openFolder": {"path": "~/Documents", "name": "Docs"}}
{"runScript": {"path": "~/.scripts/foo.sh"}}
{"systemAction": {"id": "volume-up"}}
{"notify": {"title": "Done", "body": "Build succeeded", "sound": true}}
{"windowAction": {"position": "left-half"}}
{"fakeKey": {"name": "vk1", "action": "tap"}}
{"activateLayer": {"name": "nav"}}
{"rawKanata": "(multi lctl c)"}
```

#### Behavior JSON input (all MappingBehavior variants)

```json
// Dual-role (7 tap-hold variants controlled by flags)
{"dualRole": {"tapAction": {"keystroke": {"key": "a"}}, "holdAction": {"keystroke": {"key": "lctl"}}, "tapTimeout": 200, "holdTimeout": 200, "activateHoldOnOtherKey": true}}

// Tap-dance
{"tapOrTapDance": {"tapDance": {"windowMs": 200, "steps": [{"label": "Single", "action": {"keystroke": {"key": "esc"}}}, {"label": "Double", "action": {"keystroke": {"key": "caps"}}}]}}}

// Macro
{"macro": {"text": "hello world", "source": "text"}}
{"macro": {"outputs": ["h", "e", "l", "l", "o"], "source": "keys"}}

// Chord
{"chord": {"keys": ["j", "k"], "output": {"keystroke": {"key": "esc"}}, "timeout": 200}}
```

#### Additional rule fields

| Field | Flag | Notes |
|-------|------|-------|
| Shifted output | `--shifted <key>` | e.g., `--shifted S-a` |
| Ctrl output | `--ctrl <key>` | Less common, same pattern |
| Device override | `--device <hash> --device-action <json>` | Per-device output (from DeviceKeyOverride) |
| Title | `--title <text>` | Optional human label |
| Notes | `--notes <text>` | Optional description |
| Target layer | `--layer <name>` | Which layer this rule applies to (default: base) |

#### `--dry-run` enforcement

When `--dry-run` is set, validate inputs and report what *would* happen without persisting. Output the rule JSON that would be written.

#### `--on-conflict` enforcement

| Strategy | Behavior |
|----------|----------|
| `fail` (default) | Exit 4 if input key already has a rule |
| `replace` | Overwrite existing rule silently |
| `skip` | Exit 0 with no-op message if rule exists |

#### CLIFacade additions

```swift
public func addRule(input: String, action: KeyAction, behavior: MappingBehavior?, 
                    shiftedOutput: String?, title: String?, notes: String?,
                    targetLayer: String?, deviceOverrides: [DeviceKeyOverride]?,
                    onConflict: ConflictStrategy) async throws -> RuleAddResult

public func listRules(enabledOnly: Bool) async -> [CLIRuleDetail]

public func showRule(input: String) async -> CLIRuleDetail?
```

#### New CLI types

```swift
public struct CLIRuleDetail: Codable, Sendable {
    let input: String
    let action: KeyAction
    let behavior: MappingBehavior?
    let shiftedOutput: String?
    let title: String?
    let notes: String?
    let targetLayer: String
    let deviceOverrides: [CLIDeviceOverride]?
    let isEnabled: Bool
    let createdAt: Date
}

public struct CLIDeviceOverride: Codable, Sendable {
    let deviceHash: String
    let action: KeyAction
    let behavior: MappingBehavior?
}

public enum RuleAddResult: Codable, Sendable {
    case created
    case replaced
    case skipped
    case dryRun(CLIRuleDetail)
}
```

#### Tests (~15)

- `testRuleAddSimpleCreatesRule`
- `testRuleAddWithActionJSON`
- `testRuleAddWithBehaviorJSON`
- `testRuleAddDryRunDoesNotPersist`
- `testRuleAddConflictFail`
- `testRuleAddConflictReplace`
- `testRuleAddConflictSkip`
- `testRuleAddWithShiftedOutput`
- `testRuleAddWithDeviceOverride`
- `testRuleAddWithTargetLayer`
- `testRuleListReturnsAllRules`
- `testRuleListEnabledOnlyFilters`
- `testRuleShowReturnsDetail`
- `testRuleShowNotFoundReturnsNil`
- `testRuleRemoveWithDryRun`

---

### 1B. Collection CRUD

**Goal:** Full collection lifecycle beyond enable/disable.

#### Commands

```
keypath collection create <name> [--category <cat>] [--summary <text>]
keypath collection rename <nameOrId> <newName>
keypath collection delete <nameOrId> [--force]
keypath collection duplicate <nameOrId> [--name <newName>]
keypath collection reorder <nameOrId> --position <index>
keypath collection list                              # (existing)
keypath collection enable <nameOrId>                 # (existing)
keypath collection disable <nameOrId>                # (existing)
keypath collection show <nameOrId>                   # (existing, enhance with full detail)
```

#### CLIFacade additions

```swift
public func createCollection(name: String, category: String?, summary: String?) async throws -> CLIRuleCollection
public func renameCollection(nameOrId: String, newName: String) async throws -> String?
public func deleteCollection(nameOrId: String, force: Bool) async throws -> Bool
public func duplicateCollection(nameOrId: String, newName: String?) async throws -> CLIRuleCollection
public func reorderCollection(nameOrId: String, position: Int) async throws
```

#### Tests (~8)

- `testCollectionCreate`
- `testCollectionCreateDryRun`
- `testCollectionRename`
- `testCollectionDelete`
- `testCollectionDeleteNonexistentFails`
- `testCollectionDuplicate`
- `testCollectionReorder`
- `testCollectionShowEnhanced` (full detail including mappings summary)

---

### 1C. Layer CRUD

**Goal:** Create/delete/rename layers (beyond just list/switch).

#### Commands

```
keypath layer create <name>
keypath layer delete <name>
keypath layer rename <name> <newName>
keypath layer list                    # (existing)
keypath layer switch <name>           # (existing)
```

#### Notes

Layers in KeyPath are defined by rule collections (`targetLayer` field). Creating a layer means creating a rule collection that targets it. Deleting a layer means removing rules targeting it. Need to verify the exact semantics during implementation.

#### Tests (~5)

- `testLayerCreateCreatesCollection`
- `testLayerDeleteRemovesRules`
- `testLayerRename`
- `testLayerListIncludesNewLayer`
- `testLayerDeleteNonexistentFails`

---

### 1D. Service Lifecycle

**Goal:** Full start/stop/restart via `ServiceLifecycleCoordinator`, log streaming.

#### Commands

```
keypath service start               # verifies the service becomes healthy
keypath service stop                # verifies the service stops
keypath service restart             # fails instead of reporting success when authorization is required
keypath service status           # (existing)
keypath service reload           # (existing)
keypath service logs [--lines <n>] [--follow]
keypath service level <debug|info|warning|error>
```

#### Implementation

- `start/stop/restart` delegate to `ServiceLifecycleCoordinator`
- `logs` reads from `~/Library/Logs/KeyPath/keypath-debug.log`
- `level` adjusts the runtime log level via TCP or preferences
- `--follow` uses file monitoring to tail the log (only in interactive mode)

#### CLIFacade additions

```swift
public func startService() async -> Bool
public func stopService() async -> Bool
public func restartService() async -> Bool
public func serviceLogs(lines: Int) async -> [String]
public func setLogLevel(_ level: String) async -> Bool
```

#### Tests (~6)

- `testServiceStartDelegatesToCoordinator`
- `testServiceStopDelegatesToCoordinator`
- `testServiceRestartDelegatesToCoordinator`
- `testServiceLogsReturnsLines`
- `testServiceLevelSetsPreference`
- `testServiceLogFollowExitsOnNonInteractive`

---

### 1E. Keyboard / Device Commands

**Goal:** Query connected keyboard devices, manage layouts/keymaps.

#### Commands

```
keypath keyboard devices [--json]
keypath keyboard layout [--set <id>]
keypath keyboard keymap [--set <id>]
keypath keyboard forget <deviceHash>
```

#### Notes

- `devices` lists HID devices from the device detection system
- `layout` and `keymap` get/set the PhysicalLayout and LogicalKeymap selections
- `forget` removes a device from the known-devices store

#### Tests (~4)

- `testKeyboardDevicesListsDevices`
- `testKeyboardLayoutGetAndSet`
- `testKeyboardKeymapGetAndSet`
- `testKeyboardForgetRemovesDevice`

---

### 1F. Simulate Command

**Goal:** Agent verification loop — simulate key sequences and observe outputs.

#### Command

```
keypath simulate <key-sequence> [--config <path>]
keypath simulate --raw <raw-sim-timeline> [--config <path>]
keypath simulate --sim-file <sim-file> [--config <path>]
```

#### Input format

```
# Simple key taps
keypath simulate a b
keypath simulate caps:hold a

# Raw kanata simulator timelines for overlapping key events
keypath simulate --raw 'd:f t:100 d:j t:50 u:j t:50 u:f'
keypath simulate --sim-file ./home-row-mods.sim
```

#### Output (structured JSON)

```json
{
  "events": [
    {"type": "key-output", "key": "lctl", "action": "press", "timeMs": 0},
    {"type": "layer-change", "from": "base", "to": "nav", "timeMs": 200},
    {"type": "key-output", "key": "esc", "action": "tap", "timeMs": 210}
  ],
  "finalLayer": "base",
  "durationMs": 250
}
```

#### Implementation

Delegates to `SimulatorService.simulate(taps:configPath:)` for simple tap sequences and
`SimulatorService.simulateRaw(simContent:configPath:)` for raw overlapping timelines.
Both run the bundled `kanata-simulator` binary.

#### CLIFacade additions

```swift
public func simulate(keys: [SimulatorKeyTap], configPath: String?) async throws -> CLISimulationResult
public func simulateRaw(simContent: String, configPath: String?) async throws -> CLISimulationResult
```

#### Tests (~4)

- `testSimulateSimpleKey`
- `testSimulateLayerSwitch`
- `testSimulateTapHold`
- `testSimulateInvalidKeyReturnsError`
- `testRealSimulateRawHomeRowModsOppositeHandChord`

---

### 1G. Help Schemas Enhancement

**Goal:** Expand `help-topics schemas` to cover the full rule input schema.

```
keypath help-topics schemas rule       # Show rule add JSON schema
keypath help-topics schemas action     # (existing, enhance with examples)
keypath help-topics schemas behavior   # (existing, enhance with examples)
keypath help-topics schemas collection # Show collection create schema
keypath help-topics schemas simulate   # Show simulation input format
```

Each schema output should be valid enough for an agent to construct commands without external documentation.

---

### Phase 1 Summary

| Sub-phase | New commands | New facade methods | Tests |
|-----------|-------------|-------------------|-------|
| 1A. Rule CRUD | 3 enhanced | 3 | ~15 |
| 1B. Collection CRUD | 5 new | 5 | ~8 |
| 1C. Layer CRUD | 3 new | 3 | ~5 |
| 1D. Service Lifecycle | 4 new | 5 | ~6 |
| 1E. Keyboard/Device | 4 new | 4 | ~4 |
| 1F. Simulate | 1 new | 1 | ~4 |
| 1G. Schemas | enhance | 0 | ~3 |
| **Total** | **~20 commands** | **~21 methods** | **~45 tests** |

### Phase 1 Acceptance Criteria

- [x] `swift build` compiles cleanly
- [x] `swift test --filter CLI` passes (143 tests, 0 failures)
- [x] `keypath-cli rule add caps --action '{"hyper":{}}'` works end-to-end
- [x] `keypath-cli rule add caps esc --dry-run` shows what would happen without persisting
- [x] `keypath-cli rule add caps esc --on-conflict=fail` exits 4 when rule exists
- [x] `keypath-cli collection create "My Rules"` creates collection
- [x] `keypath-cli service start/stop/restart` controls the daemon
- [ ] `keypath-cli simulate "caps:press caps:release"` returns structured events (deferred: needs binary)
- [ ] `keypath-cli keyboard devices --json` lists HID devices (deferred: needs HID access)
- [x] All new commands respect `--json`, `--dry-run`, `--on-conflict` where applicable

---

## Phase 2 — Porcelain + Ergonomics

Human-facing polish, import/export, and output stability guarantees.

### 2A. Porcelain Shortcuts

Enhance the existing porcelain with additional shortcuts:

```
keypath start       → keypath service start
keypath stop        → keypath service stop
keypath restart     → keypath service restart
keypath logs        → keypath service logs --follow
keypath unmap <key> → keypath rule remove <key> --apply
keypath list        → keypath collection list + keypath rule list (combined overview)
```

These are hidden from `--help` (like `status` and `remap`) — sugar for humans, not agents.

### 2B. Karabiner Import

```
keypath import karabiner <path-to-karabiner.json> [--collection <name>] [--dry-run]
```

Reads a Karabiner-Elements `karabiner.json` or `complex_modifications` rule file and converts to KeyPath rule collections. This is the largest user demand for migration.

#### Mapping strategy

| Karabiner concept | KeyPath equivalent |
|---|---|
| Simple modification | `rule add` with simple remap |
| Complex modification → `to` single key | `rule add` with keystroke |
| Complex modification → `to` multiple keys | `rule add` with macro behavior |
| `from.modifiers.mandatory` | Modifier prefix (e.g., `C-a`) |
| `conditions.device_if` | DeviceKeyOverride |
| `conditions.frontmost_application_if` | App condition (TBD — verify availability) |
| `to_if_alone` / `to_if_held_down` | DualRole behavior |

#### Limitations (document in output)

- Complex shell commands → `runScript` (path must exist)
- Mouse button mappings → not supported (warn and skip)
- `to_delayed_action` → no equivalent (warn and skip)

### 2C. Export / Import Round-Trip

```
keypath export collection <nameOrId> [--output <path>]
keypath export all [--output <dir>]
keypath import collection <path> [--on-conflict=fail|replace|skip]
```

Export format: JSON file matching the internal `RuleCollection` schema (or a portable subset). Import reads it back.

### 2D. Conflict Strategy Polish

`--on-conflict=merge` semantics:

- Two simple remaps for the same key with different outputs → error (ambiguous)
- A simple remap + a tap-hold where tap matches → merge into the tap-hold
- Two collections with overlapping keys → `autoResolveConflicts` pattern (newer wins)
- Document edge cases in `help-topics schemas conflict`

### 2E. Help Examples

```
keypath help-topics examples [noun]
```

Curated examples for each noun (rule, collection, service, etc.) showing common agent workflows:

```
keypath help-topics examples rule
# → Shows: "Map caps to escape", "Add home row mods", "Create a tap-dance"

keypath help-topics examples collection  
# → Shows: "Create a collection for vim keys", "Export and reimport"
```

### 2F. Output Snapshot Tests

Snapshot-style tests that capture the exact JSON output of every CLI command and fail if the shape changes. This protects the agent contract:

- Capture stdout + stderr + exit code for representative invocations
- Store as `.json.snapshot` files in the test directory
- CI fails if output diverges without explicit snapshot update (`--update-snapshots`)

### Phase 2 Summary

| Sub-phase | Scope | Tests |
|-----------|-------|-------|
| 2A. Porcelain | 6 new shortcuts | ~6 |
| 2B. Karabiner Import | 1 complex command | ~10 |
| 2C. Export/Import | 3 commands | ~8 |
| 2D. Conflict merge | Logic + schema | ~5 |
| 2E. Help examples | Content | ~3 |
| 2F. Snapshot tests | Infrastructure | ~15 |
| **Total** | **~10 commands** | **~47 tests** |

### Phase 2 Acceptance Criteria

- [x] `keypath-cli import karabiner ~/.config/karabiner/karabiner.json --dry-run` parses and reports rules
- [x] `keypath-cli export collection "Home Row Mods" --output hrm.json` exports clean JSON
- [x] `keypath-cli import collection hrm.json` restores the collection
- [x] Snapshot tests lock down output format for all commands
- [x] Porcelain shortcuts work and are hidden from `--help`

---

## Open Questions (resolve during implementation)

| Question | Phase | Notes |
|----------|-------|-------|
| App-condition storage on CustomRule | 1A | GUI uses `MapperViewModel+AppCondition.swift` but field isn't on `CustomRule`. May need model addition. |
| Layer semantics | 1C | Are layers just `targetLayer` values on collections? Can they exist independently? |
| `simulate` event stream format | 1F | Current `SimulationResult` may need enrichment for CLI output. |
| `--on-conflict=merge` rules | 2D | Need clear semantics for which merges are safe. |
| `logs --follow` on non-TTY | 1D | Should it error, or stream indefinitely? Probably error. |
| Karabiner `frontmost_application_if` | 2B | App conditions not on CustomRule yet — may be Phase 1A model work. |

---

## Out of Scope (CLI never — per #347)

- Preferences/settings (capture mode, label style, indicators)
- KindaVim configuration
- Overlay control (show/hide, position, inspector tabs)
- Custom URI scheme registration
- Menu-bar control
- QMK import
- Permissions onboarding (wizard-only)
- Packs / pack installer
