# Implementation Plan: Unify Action Data Model (#346)

## Status: In Progress

No users yet — no migration/backward-compat needed. We can change types directly.

## Upfront Design Decisions

| Decision | Recommendation |
|----------|---------------|
| Rename or extend `KeyAction`? | Extend it, rename to `Action` at the end (Phase 5) |
| Multi-key/S-expression strings? | `.keystroke(key:)` for single keys, `.rawKanata(_)` for S-expressions |
| `MacroBehavior.outputs: [String]`? | **Leave as `[String]`** — macro steps are always keystrokes/chars |
| `shiftedOutput` / `ctrlOutput`? | Promote to `KeyAction?` in Phase 3 (always simple keystrokes in practice) |

## Phases

### Phase 1 — Add missing cases to `KeyAction`

- Add `notify(title:body:sound:)`, `windowAction(position:)`, `fakeKey(name:action:)` cases
- Implement `kanataOutput` for each (all produce `push-msg` strings)
- Implement `displayName`, `autoDescription`, `commonDisplayInfo`
- Add tests
- Purely additive, no risk

### Phase 2 — Replace string action fields in behaviors

- Change `DualRoleBehavior.tapAction/holdAction`, `TapDanceStep.action`, `ChordBehavior.output` from `String` → `KeyAction`
- Update `KanataBehaviorRenderer.convertAction` to accept `KeyAction`
- Update all UI editors (mapper, behavior editor, context HUD)
- Update config generators (home-row mods, chord groups)

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

Key file:
- `Sources/KeyPathAppKit/Services/ActionDispatcher.swift`

### Phase 5 — Rename + cleanup

- Global rename `KeyAction` → `Action`
- Remove dead code, update docs

## Critical Path

```
Phase 1 → Phase 2 → Phase 3 + Phase 4 (parallel) → Phase 5
```

## Simplifications (no users)

- No migration decoders needed
- No backward-compat for persisted JSON
- No legacy string fallback paths
- Can change types directly and fix all call sites

## Notes

- `MacroBehavior.outputs` stays `[String]` — macro steps are keystroke sequences, not general actions
- The `convertAction` function handles "hyper", "meh", multi-key combos — these map to `.rawKanata(_)`
- UI editors currently use `@State` strings for tap/hold — will need conversion to `KeyAction` bindings
