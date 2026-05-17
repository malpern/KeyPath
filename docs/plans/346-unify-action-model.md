# Implementation Plan: Unify Action Data Model (#346)

## Status: Phase 3 complete — ready for Phase 4

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

### Phase 3 — Remaining string fields ✅ DONE

#### 3a — `DeviceKeyOverride.output`: `String` → `KeyAction` ✅

- `DeviceKeyOverride.output` changed from `String` to `KeyAction`
- Device-switch renderer uses `override.output.kanataOutput` and passes typed action directly for synthetic mappings
- All MapperViewModel construction sites capture `customRule.action` before overwriting with identity — eliminating the string round-trip
- 7 files changed, all 505 tests pass with identical config output (PR #352)

#### 3b — `shiftedOutput`/`ctrlOutput`: kept as `String?` (no-op) ✅

Fork rendering is string-level; promoting would round-trip through the type system. See PR #351 for rationale.

### Phase 4 — Unify ActionDispatcher

Add `dispatch(_ action: KeyAction)` that switches on the enum and calls handler logic directly. Existing URI-based `dispatch` stays for external callers.

#### Caller analysis

**Internal callers (can switch to typed dispatch):**
- `ContextHUDController.swift:256` — `dispatch(message: "layer:base")` → `dispatch(.activateLayer(name: "base"))`
- `LiveKeyboardOverlayController+KeyClickHandling.swift:42,63` — same layer:base pattern
- `LiveKeyboardOverlayController+LayerState.swift:83` — same layer:base pattern
- `LiveKeyboardOverlayController+KeyClickHandling.swift:62` — `dispatch(message: message)` where `message` comes from push-msg parsing; needs investigation

**External callers (must stay URI-routed):**
- `DeepLinkRouter.swift:26` — external `keypath://` deep links from other apps
- `RuleCollectionsManager+EventMonitoring.swift:197,212` — push-msg from kanata daemon via TCP

#### Implementation approach

Each existing `handleX(_ uri:)` method mixes URI param extraction with actual logic. To support typed dispatch:
1. Extract core logic from handlers into standalone methods (e.g., `launchApp(identifier:)`, `moveWindow(position:)`)
2. `dispatch(_ action: KeyAction)` calls these directly via enum switch
3. `dispatch(_ uri:)` continues parsing URIs and calling the same extracted methods
4. Internal callers switch from `dispatch(message:)` to `dispatch(_ action:)`

#### Decision needed

**Is this worth doing now?** The internal callers are almost all `dispatch(message: "layer:base")` — a narrow use case. The real value of typed dispatch would come when internal code constructs actions programmatically (e.g., dispatching a `.launchApp` from a button click). If no such use case exists yet, Phase 4 could be deferred.

Files:
- `Sources/KeyPathAppKit/Services/ActionDispatcher.swift` — main refactor
- `Sources/KeyPathAppKit/UI/ContextHUD/ContextHUDController.swift` — caller update
- `Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayController+KeyClickHandling.swift` — caller update
- `Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayController+LayerState.swift` — caller update

### Phase 5 — Rename + cleanup

- Global rename `KeyAction` → `Action` (or `MappingAction` — decide then)
- Remove dead code, update docs

## Critical Path

```
Phase 1 ✅ → Phase 2 ✅ → Phase 3 ✅ → Phase 4 (decide scope) → Phase 5
```

## Safety Net

71 tests added before any changes (commit c3b4880e):
- `KeyActionTests` — kanataOutput, displayName, outputString for every case
- `ConvertActionSnapshotTests` — every convertAction input pattern
- `BehaviorRenderingGoldenTests` — exact string output for all behavior variants

**Verification strategy:** After changing types, all golden tests must pass unchanged. If any test breaks, the refactor changed observable config output. This held through Phases 2 and 3 — all 505 tests passed after each migration.

## Simplifications (no users)

- No migration decoders needed
- No backward-compat for persisted JSON
- No legacy string fallback paths
- Can change types directly and fix all call sites

## Notes

- `MacroBehavior.outputs` stays `[String]` — macro steps are keystroke sequences, not general actions
- `parseActionString()` normalizes keys via `KanataKeyConverter` at construction time, so model holds already-normalized values
- The renderer's `renderHyperWithLayers()` produces context-dependent output that can't live in `KeyAction.kanataOutput` (needs layer infos from the config generator context)
