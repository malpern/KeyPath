# TCP Overlay Events - KeyPath Fork

This document tracks the TCP events available for keyboard overlay visualization.

## Implemented Events

| Event | Purpose | Status |
|-------|---------|--------|
| `KeyInput` | Physical key press/release | ✅ Implemented |
| `KeyOutput` | Synthetic key output (what Kanata emits) | ✅ Implemented |
| `HoldActivated` | Tap-hold key enters hold state | ✅ Implemented |
| `TapActivated` | Tap-hold key triggers tap action | ✅ Implemented |
| `LayerChange` | Active layer changed | ✅ Upstream |

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
{"HoldActivated": {"key": "caps", "action": "", "t": 12400}}
```
Sent when a tap-hold key crosses the hold threshold. The overlay can show a special indicator (e.g., ✦) on the physical key.

### TapActivated
```json
{"TapActivated": {"key": "caps", "action": "", "t": 12350}}
```
Sent when a tap-hold key triggers its tap action. The overlay can suppress the output key (e.g., ESC) since the physical key (caps) is already shown.

## Potential Future Events

These events might be useful but are not currently implemented:

| Event | Purpose | Priority |
|-------|---------|----------|
| `OneShotActivated` | One-shot modifier activated | Low |
| `ChordResolved` | Chord/combo resolved to action | Low |
| `MacroStarted` | Macro execution began | Low |
| `TapDanceResolved` | Tap-dance resolved to action | Low |

### Why These Might Be Useful

1. **OneShotActivated** - One-shot modifiers (e.g., sticky shift) could show a special indicator similar to HoldActivated.

2. **ChordResolved** - When a chord (e.g., `sd` pressed together) resolves to an action, the overlay could show which chord was recognized.

3. **MacroStarted** - When a macro fires, show the macro name rather than lighting up each individual key the macro types.

4. **TapDanceResolved** - Similar to TapActivated, but for tap-dance keys that have multiple tap counts.

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
    "key_input"
  ]
}
```

## Usage in KeyPath

The `KeyboardVisualizationViewModel` handles these events:

1. **KeyInput** → Updates `tcpPressedKeyCodes` (physical keys currently pressed)
2. **HoldActivated** → Shows ✦ indicator, stores in `holdLabels`
3. **TapActivated** → Tracks which outputs to suppress (prevents ESC lighting up when caps is tapped)
4. **LayerChange** → Updates `currentLayerName` for layer-specific emphasis
