# Implementation Plan: Unify Action Data Model (#346)

## Status: Phase 2 complete — resolve merge conflicts, then Phase 3a

No users yet — no migration/backward-compat needed. We can change types directly.

## Decisions Made

| Decision | Resolution |
|----------|-----------|
| Rename or extend `KeyAction`? | Extend it, rename to `Action` at the end (Phase 5) |
| Multi-key/S-expression strings? | `.keystroke(key:)` for single keys, `.rawKanata(_)` for S-expressions |
| `MacroBehavior.outputs: [String]`? | **Leave as `[String]`** — macro steps are always keystrokes/chars |
| `shiftedOutput` / `ctrlOutput`? | **Keep as `String?`** — always simple keystrokes; fork rendering is string-level (see Phase 3b rationale) |
| Hyper/Meh: first-class cases? | **Yes** — `.hyper` and `.meh` are dedicated enum cases |
| `convertAction` refactor strategy? | Parse string → `KeyAction` → `.kanataOutput` (single source of truth) |
| Hyper with linked layers? | Stays in renderer (`renderHyperWithLayers`) since it depends on context |
| Final rename target? | TBD — `Action` is generic, consider `MappingAction` or keep `KeyAction` |
| UI layer strings? | **Keep as `String`** — AdvancedBehaviorManager/MappingBehaviorEditor are presentation boundaries for TextField bindings. Shared model is fully typed; no new capability from pushing KeyAction into view state. |

## Phases

### Phase 1 — Add missing cases to `KeyAction` ✅ DONE

Added: `.hyper`, `.meh`, `.notify(title:body:sound:)`, `.windowAction(position:)`, `.fakeKey(name:action:)`

Implemented `kanataOutput`, `displayName`, `autoDescription`, `commonDisplayInfo`, type checks.
Added `FakeKeyAction` enum (tap/press/release/toggle).

### Phase 2 — Replace string action fields in behaviors ✅ DONE

**Early Phase 2 (convertAction refactor):**
- `convertAction` now parses string → `KeyAction` → `.kanataOutput`
- `parseActionString()` exposed as public static method

**Full Phase 2 (behavior model types):**
- `DualRoleBehavior.tapAction/holdAction`: `String` → `KeyAction`
- `TapDanceStep.action`: `String` → `KeyAction`
- `ChordBehavior.output`: `String` → `KeyAction`
- `KanataBehaviorRenderer.convertAction` accepts `KeyAction` directly
- Added `convertActionFromString` for legacy UI boundary use
- Added `KeyAction.empty` / `.isEmpty` for unconfigured state
- Added `.tapActionString` / `.holdActionString` / `.actionString` / `.outputString` bridge accessors
- 30 source files, 11 test files updated (~144 call sites)
- All 494 tests pass with identical kanata config output

**UI layer left as String (by design):**
- `AdvancedBehaviorManager.holdAction`, `.doubleTapAction`, `.comboOutput`, `.tapDanceSteps` stay `String`
- `MappingBehaviorEditor` `@State` vars stay `String`
- Conversion at boundary: `.outputString` when reading, `parseActionString()` when writing
- These are TextField binding concerns, not shared model — no capability gap

### Phase 3 — Remaining string fields

**Prerequisite:** Resolve merge conflicts (`UU` state) in `KeyAction.swift`, `MappingBehavior.swift`, and `SnapshotHelpers.swift` before starting.

#### 3a — `DeviceKeyOverride.output`: `String` → `KeyAction`

Straightforward. Callers already have a `KeyAction` and convert to string via `.kanataOutput` to construct overrides — they'd just pass the typed value directly.

Files:
- `Sources/KeyPathAppKit/Models/KeyMapping.swift` — struct definition + Codable
- `Sources/KeyPathAppKit/Models/CustomRule.swift` — `[DeviceKeyOverride]?` flows through
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfiguration+DeviceSwitch.swift` — replace `convertToKanataSequence(override.output)` with `override.output.kanataOutput`; remove synthetic `.keystroke(key: override.output)` (already a `KeyAction`)
- `Sources/KeyPathAppKit/UI/Experimental/MapperViewModel+LayerManagement.swift` — 5 sites constructing `DeviceKeyOverride(... output: action.kanataOutput ...)` → pass `action` directly
- `Sources/KeyPathAppKit/UI/Experimental/MapperViewModel+ConflictResolution.swift` — override construction
- `Sources/KeyPathAppKit/UI/Previews/PreviewFixtures.swift` — literal `"lctl"` → `.keystroke(key: "lctl")`
- `Tests/KeyPathTests/Models/CustomRuleDeviceOverrideTests.swift` — test fixtures

**Decision:** Use full `KeyAction` (not a narrower type). Device overrides already carry `behavior: MappingBehavior?`, so the output can semantically be any action. Keeps the model uniform with `KeyMapping.action`.

#### 3b — `shiftedOutput`/`ctrlOutput`: **keep as `String?`** (revised)

These are always simple keystroke strings (`"M-down"`, `"at"`, `"pgup"`). The fork rendering pipeline (`buildForkDefinition` → `convertToForkAction` → `normalizeForkOutput` → `convertSingleKeyToForkFormat`) is fundamentally string-level — it splits tokens, detects modifier prefixes, and reformats for fork syntax. Promoting to `KeyAction` would mean:

1. The model stores `.keystroke(key: "M-down")`
2. Fork rendering calls `.kanataOutput` to get `"M-down"` back
3. Then re-parses the string for fork-specific formatting

That's round-tripping through the type system with no safety benefit. The UI layer (`MapperViewModel`) also works with these as raw strings throughout its recording/preset/save pipeline (~20 call sites for `shiftedOutput` alone).

**Alternative considered:** `KeyAction?` with fork renderer pattern-matching on enum cases. Rejected because fork formatting is a kanata syntax concern (modifier prefixes must become `(multi ...)` inside fork), not domain modeling.

**No code changes needed for 3b.** These fields stay as-is.

### Phase 4 — Unify ActionDispatcher

- Add `dispatch(_ action: KeyAction)` that switches on the enum directly
- URI parsing becomes a thin fallback for external/kanata-originated messages
- Internal callers pass typed values
- Clarification: push-msg-originated actions (from kanata daemon) remain URI-routed

Key file:
- `Sources/KeyPathAppKit/Services/ActionDispatcher.swift`

### Phase 5 — Rename + cleanup

- Global rename `KeyAction` → `Action` (or `MappingAction` — decide then)
- Remove dead code, update docs

## Critical Path

```
Phase 1 ✅ → Phase 2 ✅ → resolve merges → Phase 3a + Phase 4 (parallel) → Phase 5
                                            (3b: no-op, kept as String)
```

## Safety Net

71 tests added before any changes (commit c3b4880e):
- `KeyActionTests` — kanataOutput, displayName, outputString for every case
- `ConvertActionSnapshotTests` — every convertAction input pattern
- `BehaviorRenderingGoldenTests` — exact string output for all behavior variants

**Verification strategy:** After changing types, all golden tests must pass unchanged. If any test breaks, the refactor changed observable config output. This held through Phase 2 — all 494 tests passed after the migration.

## Simplifications (no users)

- No migration decoders needed
- No backward-compat for persisted JSON
- No legacy string fallback paths
- Can change types directly and fix all call sites

## Notes

- `MacroBehavior.outputs` stays `[String]` — macro steps are keystroke sequences, not general actions
- `parseActionString()` normalizes keys via `KanataKeyConverter` at construction time, so model holds already-normalized values
- The renderer's `renderHyperWithLayers()` produces context-dependent output that can't live in `KeyAction.kanataOutput` (needs layer infos from the config generator context)
