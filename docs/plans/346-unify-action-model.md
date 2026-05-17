# Implementation Plan: Unify Action Data Model (#346)

## Status: Phase 1 complete, early Phase 2 complete

No users yet — no migration/backward-compat needed. We can change types directly.

## Decisions Made

| Decision | Resolution |
|----------|-----------|
| Rename or extend `KeyAction`? | Extend it, rename to `Action` at the end (Phase 5) |
| Multi-key/S-expression strings? | `.keystroke(key:)` for single keys, `.rawKanata(_)` for S-expressions |
| `MacroBehavior.outputs: [String]`? | **Leave as `[String]`** — macro steps are always keystrokes/chars |
| `shiftedOutput` / `ctrlOutput`? | Promote to `KeyAction?` in Phase 3 (always simple keystrokes in practice) |
| Hyper/Meh: first-class cases? | **Yes** — `.hyper` and `.meh` are dedicated enum cases |
| `convertAction` refactor strategy? | Parse string → `KeyAction` → `.kanataOutput` (single source of truth) |
| Hyper with linked layers? | Stays in renderer (`renderHyperWithLayers`) since it depends on context |
| Final rename target? | TBD — `Action` is generic, consider `MappingAction` or keep `KeyAction` |

## Phases

### Phase 1 — Add missing cases to `KeyAction` ✅ DONE

Added: `.hyper`, `.meh`, `.notify(title:body:sound:)`, `.windowAction(position:)`, `.fakeKey(name:action:)`

Implemented `kanataOutput`, `displayName`, `autoDescription`, `commonDisplayInfo`, type checks.
Added `FakeKeyAction` enum (tap/press/release/toggle).

### Phase 2 — Replace string action fields in behaviors

**Early Phase 2 (convertAction refactor) ✅ DONE:**
- `convertAction` now parses string → `KeyAction` → `.kanataOutput`
- `parseActionString()` exposed as public static method
- All 494 tests pass with identical output (proving behavioral equivalence)

**Remaining Phase 2 (next session):**
- Change `DualRoleBehavior.tapAction/holdAction` from `String` → `KeyAction`
- Change `TapDanceStep.action` from `String` → `KeyAction`
- Change `ChordBehavior.output` from `String` → `KeyAction`
- Update `KanataBehaviorRenderer.convertAction` to accept `KeyAction` directly
- Update all UI editors (mapper, behavior editor, context HUD)
- Update config generators (home-row mods, chord groups)
- ~230 call sites (mechanical, safe with existing test coverage)

Key files:
- `Sources/KeyPathAppKit/Models/MappingBehavior.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataBehaviorRenderer.swift`
- `Sources/KeyPathAppKit/UI/Experimental/MapperViewModel.swift`
- `Sources/KeyPathAppKit/UI/Experimental/MappingBehaviorEditor.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfiguration+MappingGenerators.swift`

### Phase 3 — Remaining string fields

- `KeyMapping.shiftedOutput/ctrlOutput` → `KeyAction?`
- `DeviceKeyOverride.output` → `KeyAction`
- Update fork rendering and device-switch config generator

Key files:
- `Sources/KeyPathAppKit/Models/KeyMapping.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/KanataConfiguration+DeviceSwitch.swift`

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
Phase 1 ✅ → Phase 2 (in progress) → Phase 3 + Phase 4 (parallel) → Phase 5
```

## Safety Net

71 tests added before any changes (commit c3b4880e):
- `KeyActionTests` — kanataOutput, displayName, outputString for every case
- `ConvertActionSnapshotTests` — every convertAction input pattern
- `BehaviorRenderingGoldenTests` — exact string output for all behavior variants

**Verification strategy for Phase 2:** After changing types, all golden tests must pass unchanged. If any test breaks, the refactor changed observable config output.

## Simplifications (no users)

- No migration decoders needed
- No backward-compat for persisted JSON
- No legacy string fallback paths
- Can change types directly and fix all call sites

## Notes

- `MacroBehavior.outputs` stays `[String]` — macro steps are keystroke sequences, not general actions
- UI editors currently use `@State` strings for tap/hold — will need conversion to `KeyAction` bindings
- `parseActionString()` can be used at UI boundaries to convert user-entered strings to `KeyAction`
- The renderer's `renderHyperWithLayers()` produces context-dependent output that can't live in `KeyAction.kanataOutput` (needs layer infos from the config generator context)
