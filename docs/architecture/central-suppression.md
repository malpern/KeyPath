# Key Suppression System (Centralized)

This document describes the centralized key suppression system for the keyboard overlay visualization.
**Status:** Implemented (Phases 1 & 2 complete as of January 4, 2026)

## Overview

When keys are remapped (e.g., A→B) or use tap-hold behaviors (e.g., CapsLock = tap:Esc, hold:Hyper), the overlay should only highlight the **physical key pressed**, not the output key that Kanata produces.

## Goals

- **Primary goal:** suppress output key highlights for simple remaps (A→B).
- Provide a **single decision point** so new suppression types (chords, macros, sequences) can plug in without touching every handler.
- Keep suppression logic **data-driven** (computed sets), not scattered across handlers.

## Non-Goals (for this proposal)

- Perfect suppression for every Kanata feature on day one.
- Replacing the CGEvent or TCP pipelines.
- Changing the visual layer/label logic.

## Current Implementation

- A unified `shouldSuppressKeyHighlight(_:)` method is called from all event handlers (CGEvent, TCP, flagsChanged).
- Remap suppression derives from TCP physical keys (`tcpPressedKeyCodes`) for correctness.
- Tap-hold suppression (`suppressedOutputKeyCodes`) and remap suppression (`suppressedRemapOutputKeyCodes`) are combined in the unified check.
- `recentTapOutputs` and `recentRemapSourceKeyCodes` provide 150ms delayed suppression windows.
- Gap fixes implemented:
  - `handleFlagsChanged()` now calls `shouldSuppressKeyHighlight()` before updating modifier state.
  - Suppressed key releases clear `holdActiveKeyCodes` to prevent visual artifacts.
  - Layer changes clear `activeTapHoldSources` to prevent stale suppressions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  SUPPRESSION DATA SOURCES                       │
├─────────────────────────────────────────────────────────────────┤
│ Tap-Hold:                    │ Simple Remap:                    │
│ - dynamicTapHoldOutputMap    │ - remapOutputMap                 │
│ - fallbackTapHoldOutputMap   │                                  │
│ - activeTapHoldSources       │                                  │
│ - recentTapOutputs           │                                  │
│                              │ - recentRemapSourceKeyCodes      │
├─────────────────────────────────────────────────────────────────┤
│              COMPUTED SUPPRESSION SETS                          │
│ - suppressedOutputKeyCodes   │ - suppressedRemapOutputKeyCodes  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              SINGLE UNIFIED SUPPRESSION CHECK                   │
│                                                                 │
│  shouldSuppressKeyHighlight(_ keyCode: UInt16) -> Bool          │
│                                                                 │
│  Combines all suppression sources into one decision point.      │
│  All event handlers call this method.                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    EVENT HANDLERS                               │
├─────────────────────────────────────────────────────────────────┤
│ handleKeyEvent()      │ CGEvent keyDown/keyUp                   │
│ handleTcpKeyInput()   │ Kanata TCP KeyInput events              │
│ handleFlagsChanged()  │ Modifier key state changes              │
└─────────────────────────────────────────────────────────────────┘
```

## Suppression Types

### 1. Tap-Hold Suppression

When a tap-hold key (e.g., CapsLock) is configured to emit a different key on tap (e.g., Escape), we suppress the output key.

**Data structures:**
- `dynamicTapHoldOutputMap`: Maps source keyCode → Set of output keyCodes (populated from TapActivated events)
- `fallbackTapHoldOutputMap`: Static fallback for common patterns (caps → esc)
- `activeTapHoldSources`: Currently-pressed tap-hold source keys
- `recentTapOutputs`: Output keys to suppress briefly after TapActivated fires (150ms window)

**Computed set:** `suppressedOutputKeyCodes`

### 2. Simple Remap Suppression

When a key is remapped (A→B), pressing A should not also highlight B. This is the primary goal.

**Data structures:**
- `remapOutputMap`: Maps input keyCode → output keyCode (built from layerKeyMap)
- `recentRemapSourceKeyCodes`: Recently released remap source keys kept briefly to suppress delayed outputs (150ms)

**Computed set:** `suppressedRemapOutputKeyCodes` (computed from currently pressed keys plus `recentRemapSourceKeyCodes`)

## Event Flow Examples (Target Behavior)

### Example: Simple Remap (A→B)

```
1. User presses A (physical)
   → TCP KeyInput: key="a", action="press"
   → tcpPressedKeyCodes.insert(0)  ✓ Shows "A" pressed

2. Kanata outputs B
   → CGEvent keyDown(B)
   → shouldSuppressKeyHighlight(11) = true
   → SUPPRESSED - B does NOT light up

3. User releases A
   → TCP KeyInput: key="a", action="release"
   → tcpPressedKeyCodes.remove(0)

4. Kanata outputs B release
   → CGEvent keyUp(B)
   → shouldSuppressKeyHighlight(11) = true
   → SUPPRESSED
```

### Example: Tap-Hold (CapsLock → Esc)

```
1. User presses CapsLock
   → TCP KeyInput: key="caps", action="press"
   → activeTapHoldSources.insert(57)
   → tcpPressedKeyCodes.insert(57)  ✓ Shows "CapsLock" pressed

2. Kanata outputs Esc
   → CGEvent keyDown(esc)
   → shouldSuppressKeyHighlight(53) = true
   → SUPPRESSED - Esc does NOT light up

3. User releases CapsLock
   → TCP KeyInput: key="caps", action="release"
   → activeTapHoldSources delayed removal (200ms)

4. TapActivated fires
   → recentTapOutputs.insert(53) for 150ms
   → Catches any late Esc keystrokes
```

## Adding New Suppression Types

To add support for new behaviors (chords, macros, sequences), the only required change is to add a new computed suppression set and include it in the unified check:

1. Create a computed set for the new suppression type:
   ```swift
   private var suppressedChordOutputKeyCodes: Set<UInt16> { ... }
   ```

2. Add one line to `shouldSuppressKeyHighlight()`:
   ```swift
   private func shouldSuppressKeyHighlight(_ keyCode: UInt16) -> Bool {
       suppressedOutputKeyCodes.contains(keyCode)
           || recentTapOutputs.contains(keyCode)
           || suppressedRemapOutputKeyCodes.contains(keyCode)
           || suppressedChordOutputKeyCodes.contains(keyCode)  // NEW
   }
   ```

No changes needed to individual event handlers once the unified check is in place.

## Key File

All suppression logic lives in:
`Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel.swift`

## Implementation Plan (Phased)

### Phase 1: Centralize A→B suppression (primary goal)

- Status: **Done** (January 4, 2026)
- Introduce `shouldSuppressKeyHighlight(_:)` in the view model.
- Use it from **all** event handlers (CGEvent keyDown/keyUp, TCP KeyInput, flagsChanged).
- Centralize A→B suppression behind the unified check.

### Phase 2: Tap-hold + delayed output windows

- Status: **Done** (January 4, 2026)
- Add `recentTapOutputs` into the unified suppression decision.
- Keep the 150ms suppression window as a temporary guard for delayed outputs.

### Phase 3: Chord/Macro/Sequence suppression (Future Work)

- Status: **Not Started** - Requires Kanata TCP protocol changes
- GitHub Issue: #77
- Add computed sets for chords/macros/sequences as needed.
- Keep additions to one line in `shouldSuppressKeyHighlight(_:)`.

**Investigation Findings (January 4, 2026):**

The TCP protocol already defines the message types we need in `External/kanata/tcp_protocol/src/lib.rs`:
```rust
ChordResolved { keys: String, action: String, t: u64 }
TapDanceResolved { key: String, tap_count: u8, action: String, t: u64 }
```

However, the emit functions are **not implemented** in the Kanata fork. The work required:

1. **keyberon/src/layout.rs** (~2-3 hours):
   - Add `chord_resolved: Option<ChordResolvedInfo>` field
   - Add `tap_dance_resolved: Option<TapDanceResolvedInfo>` field
   - Add `take_chord_resolved()` and `take_tap_dance_resolved()` methods
   - Follow the existing `hold_activated`/`tap_activated` pattern

2. **keyberon/src/chord.rs** (~line 503):
   - Set `chord_resolved` when `self.active_chords.push(ach)` succeeds

3. **kanata/src/kanata/mod.rs** (~1 hour):
   - Call `layout.take_chord_resolved()` after tick()
   - Call `layout.take_tap_dance_resolved()` after tick()
   - Emit `ServerMessage::ChordResolved` / `TapDanceResolved`

4. **KeyPath Swift** (~1 hour):
   - Parse new TCP message types in `KanataTcpClient`
   - Build `suppressedChordOutputKeyCodes` set
   - Add to `shouldSuppressKeyHighlight()`

**Challenge:** Extracting chord output keys from keyberon's borrow-checker scope. May need to send participating key names and have KeyPath look up outputs from config (same workaround used for `TapActivated`).

## Testing Checklist

- [x] Tap-hold: Press caps lock, verify ESC doesn't light up (January 4, 2026)
- [x] Simple remap: Create A→B, press A, verify only A lights up (January 4, 2026)
- [ ] Modifier remap: If A→Shift, verify Shift doesn't light up (blocked by #76 - modifier recording bug)
- [x] Layer switch: Switch layers while holding tap-hold key, verify no stale suppression (January 4, 2026)
- [x] Hold state: Verify held keys don't linger after suppression clears (January 4, 2026)

## Diagnostics

- **Verbose mode:** Enable detailed suppression logs via `FeatureFlags.keyboardSuppressionDebugEnabled` (UserDefaults key `KEYBOARD_SUPPRESSION_DEBUG_ENABLED`).
- **Standard debug logs:** Basic key events logged at debug level (`⌨️ [KeyboardViz]` prefix).
