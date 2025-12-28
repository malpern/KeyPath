# TCP Overlay Events - KeyPath Fork

This document tracks the TCP events available for keyboard overlay visualization.

## Implemented Events

| Event | Purpose | Protocol | Emission | Swift |
|-------|---------|----------|----------|-------|
| `KeyInput` | Physical key press/release | ✅ | ✅ | ✅ |
| `KeyOutput` | Synthetic key output (what Kanata emits) | ✅ | ✅ | ✅ |
| `HoldActivated` | Tap-hold key enters hold state | ✅ | ✅ | ✅ |
| `TapActivated` | Tap-hold key triggers tap action | ✅ | ✅ | ✅ |
| `OneShotActivated` | One-shot modifier activated | ✅ | ⏳ Future | ✅ |
| `ChordResolved` | Chord/combo resolved to action | ✅ | ⏳ Future | ✅ |
| `TapDanceResolved` | Tap-dance resolved to action | ✅ | ⏳ Future | ✅ |
| `LayerChange` | Active layer changed | ✅ Upstream | ✅ Upstream | ✅ |

**Legend:**
- Protocol: TCP message type defined in `tcp_protocol/src/lib.rs`
- Emission: Kanata emits the event in keyberon/processing code
- Swift: KeyPath can receive and handle the event

## Event Details

### KeyInput
```json
{"KeyInput": {"key": "caps", "action": "press", "t": 12345}}
```
Sent when the user physically presses or releases a key. The `key` is the raw physical key name.

### KeyOutput
```json
{"KeyOutput": {"key": "esc", "action": "press", "t": 12346}}
```
Sent when Kanata emits a synthetic key to the OS. Useful for understanding what remapping occurred.

### HoldActivated
```json
{"HoldActivated": {"key": "caps", "action": "lctl+lmet+lalt+lsft", "t": 12400}}
```
Sent when a tap-hold key crosses the hold threshold. The overlay shows ✦ (Hyper) indicator on the physical key.

### TapActivated
```json
{"TapActivated": {"key": "caps", "action": "esc", "t": 12350}}
```
Sent when a tap-hold key triggers its tap action. The overlay suppresses the output key (ESC) since the physical key (caps) is already shown.

### OneShotActivated
```json
{"OneShotActivated": {"key": "lsft", "modifiers": "lsft", "t": 12500}}
```
Sent when a one-shot modifier key is activated. Could show a special indicator like HoldActivated.

**Status:** Protocol defined, Swift handler ready. Kanata emission point in keyberon one-shot logic not yet implemented.

### ChordResolved
```json
{"ChordResolved": {"keys": "s+d", "action": "esc", "t": 12600}}
```
Sent when a chord (multi-key combo like `sd` pressed together) resolves to an action.

**Status:** Protocol defined, Swift handler ready. Kanata emission point in keyberon chord logic not yet implemented.

### TapDanceResolved
```json
{"TapDanceResolved": {"key": "q", "tap_count": 2, "action": "alt+tab", "t": 12700}}
```
Sent when a tap-dance resolves to a specific action based on tap count.

**Status:** Protocol defined, Swift handler ready. Kanata emission point in keyberon tap-dance logic not yet implemented.

## Current Capabilities Advertised

From `HelloOk` response:
```json
{
  "capabilities": [
    "reload",
    "status",
    "ready",
    "hold_activated",
    "tap_activated",
    "oneshot_activated",
    "chord_resolved",
    "tap_dance_resolved",
    "key_input"
  ]
}
```

## Usage in KeyPath

The `KeyboardVisualizationViewModel` handles these events:

1. **KeyInput** → Updates `tcpPressedKeyCodes` (physical keys currently pressed)
2. **HoldActivated** → Shows ✦ indicator, stores in `holdLabels`
3. **TapActivated** → Populates `dynamicTapHoldOutputMap`, suppresses output keys
4. **LayerChange** → Updates `currentLayerName` for layer-specific emphasis

## Future Work: Kanata Emission Points

The following events need emission points added to keyberon:

### OneShotActivated
Location: `keyberon/src/layout.rs` in the one-shot state machine
- When a one-shot key is activated and the modifier is applied
- Similar pattern to `tap_activated` but for `OneShot` action type

### ChordResolved
Location: `keyberon/src/layout.rs` in chord/combo resolution logic
- When a chord is recognized and its action is executed
- Need to emit the constituent keys and resolved action

### TapDanceResolved
Location: `keyberon/src/layout.rs` in tap-dance timeout/resolution
- When tap-dance timer expires and action is chosen
- Need to emit key, tap count, and resolved action

These are complex changes because:
1. Each feature has its own state machine in keyberon
2. Need to pass TCP sender through the call chain
3. Must be careful about performance (these are in hot paths)
