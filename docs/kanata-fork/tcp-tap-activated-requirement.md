# TCP TapActivated Message Requirement

**Status: IMPLEMENTED** (2024-12-27)

## Problem

When a tap-hold key (e.g., capslock) triggers its **tap** action (e.g., emit ESC), the keyboard overlay shows both the physical key AND the output key lighting up. This is confusing - users want to see only the physical key they pressed.

### Current Behavior

```
User taps capslock (configured: tap=esc, hold=hyper)

TCP Messages received:
1. KeyInput { key: "caps", action: "press", t: 100 }
2. KeyInput { key: "esc", action: "press", t: 150 }   ← Output key
3. KeyInput { key: "esc", action: "release", t: 160 }
4. KeyInput { key: "caps", action: "release", t: 170 }

Result: Both capslock AND ESC light up on overlay
```

### Desired Behavior

```
User taps capslock

TCP Messages received:
1. KeyInput { key: "caps", action: "press", t: 100 }
2. TapActivated { key: "caps", action: "esc", t: 150 }  ← NEW
3. KeyInput { key: "caps", action: "release", t: 170 }

Result: Only capslock lights up, ESC suppressed
```

## Proposed Solution

Add a new `TapActivated` server message, symmetric to the existing `HoldActivated`:

```rust
/// Sent when a tap-hold key triggers its tap action
TapActivated {
    /// Physical key name (e.g., "caps")
    key: String,
    /// Tap action output (e.g., "esc")
    action: String,
    /// Timestamp in milliseconds since Kanata start
    t: u64,
},
```

## Implementation Location

The `HoldActivated` emission point is in `src/kanata/mod.rs` where tap-hold state transitions occur. `TapActivated` should be emitted at the symmetric location when Kanata decides a tap-hold resolves to tap (not hold).

Look for where:
1. The tap-hold timeout expires without the key being held long enough
2. The tap action is executed (key output emitted)

## KeyPath Client Changes

Once `TapActivated` is available, `KeyboardVisualizationViewModel` can:

1. Track `TapActivated` messages to know which physical key produced which output
2. Automatically suppress output keys that came from tap-hold sources
3. Remove the hardcoded `tapHoldOutputMap` workaround

```swift
// When TapActivated received:
case let .tapActivated(key, action, _):
    let sourceKeyCode = kanataNameToKeyCode(key)
    let outputKeyCode = kanataNameToKeyCode(action)
    // Suppress outputKeyCode from lighting up
    tapOutputSuppression[sourceKeyCode] = outputKeyCode
```

## Existing HoldActivated Reference

For reference, `HoldActivated` is already working:

```rust
ServerMessage::HoldActivated {
    key: String,      // e.g., "caps"
    action: String,   // e.g., "lctl+lmet+lalt+lsft"
    t: u64,
}
```

The client uses this to show a ✦ symbol on the key and avoid lighting up individual modifier keys.

## Priority

Medium - Current workaround (hardcoded capslock→esc mapping) works for the most common case, but a proper solution is needed for users with other tap-hold configurations.

## Related Files

- `External/kanata/tcp_protocol/src/lib.rs` - Protocol definition
- `External/kanata/src/kanata/mod.rs` - Event emission (search for `emit_hold_activated`)
- `Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel.swift` - Client handler
