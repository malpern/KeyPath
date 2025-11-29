# Tap-Hold and Tap-Dance Support

KeyPath supports advanced key behaviors beyond simple remapping:

- **Tap-Hold (Dual-Role)**: A key that does one thing when tapped quickly, another when held.
- **Tap-Dance**: A key that does different things based on how many times you tap it.

## UI Overview

When editing a Custom Rule, you'll see a **Simple / Advanced** toggle:

- **Simple**: Standard input → output mapping (e.g., Caps Lock → Escape)
- **Advanced**: Configure tap/hold actions, tap-dance patterns, and timing

### Dual-Role (Tap/Hold)

In Advanced mode, select "Tap / Hold" to configure:

| Field | Description |
|-------|-------------|
| Tap action | What happens on a quick tap (e.g., type "a") |
| Hold action | What happens when held (e.g., activate Left Control) |
| Tapping term | Milliseconds before a press becomes a hold (default: 200ms) |
| Activate hold on other key | If enabled, pressing another key while this key is down triggers the hold action immediately |
| Quick tap | If enabled, very fast taps always register as tap even if another key was pressed |

#### Kanata Variants

Based on the flags you set, KeyPath emits the appropriate Kanata syntax:

| Flags | Kanata Syntax |
|-------|---------------|
| Default | `(tap-hold 200 200 a lctl)` |
| Activate hold on other key | `(tap-hold-press 200 200 a lctl)` |
| Quick tap | `(tap-hold-release 200 200 a lctl)` |

### Tap-Dance

Select "Tap Dance" to configure multiple actions:

| Field | Description |
|-------|-------------|
| Pattern window | Milliseconds to wait for additional taps (default: 200ms) |
| Steps | Ordered list of actions (single tap, double tap, etc.) |

Example: Caps Lock could be configured as:
- Single tap → Escape
- Double tap → Caps Lock
- Triple tap → Open Spotlight

Kanata syntax: `(tap-dance 200 (esc caps M-spc))`

## Home Row Mods

A popular use case for dual-role keys is "home row mods"—using the home row letters as modifiers when held:

| Key | Tap | Hold |
|-----|-----|------|
| A | a | Left Control |
| S | s | Left Option |
| D | d | Left Command |
| F | f | Left Shift |
| J | j | Right Shift |
| K | k | Right Command |
| L | l | Right Option |
| ; | ; | Right Control |

KeyPath provides a `homeRowMod` factory that pre-configures recommended settings:
- `activateHoldOnOtherKey: true` — hold triggers when you press another key
- `quickTap: true` — fast typing still produces letters

## Side-Channel Telemetry (Future)

When Kanata supports reporting tap vs hold resolutions, KeyPath will consume this data to show:

- Which action was triggered (tap or hold)
- Timing information for debugging
- Layer state changes from tap-dance patterns

### Proposed Schema

```json
{
  "type": "behavior_resolution",
  "key_id": "beh_base_a",
  "resolution": "tap" | "hold" | "dance_step",
  "step_index": 0,
  "timestamp_ms": 1234567890,
  "duration_ms": 150
}
```

This will enable the UI to:
- Highlight which action fired on a keyboard visualization
- Show timing feedback for tuning tapping terms
- Debug unexpected behavior

## Technical Details

### Data Model

```swift
enum MappingBehavior {
    case dualRole(DualRoleBehavior)
    case tapDance(TapDanceBehavior)
}

struct DualRoleBehavior {
    var tapAction: String
    var holdAction: String
    var tapTimeout: Int        // default 200
    var holdTimeout: Int       // default 200
    var activateHoldOnOtherKey: Bool
    var quickTap: Bool
}

struct TapDanceBehavior {
    var windowMs: Int          // default 200
    var steps: [TapDanceStep]
}
```

### Round-Trip Support

KeyPath can parse its own generated Kanata syntax back into `MappingBehavior` for diagnostics:

```swift
let rendered = KanataBehaviorRenderer.render(mapping)
// "(tap-hold-press 200 200 a lctl)"

let parsed = KanataBehaviorParser.parse(rendered)
// .dualRole(DualRoleBehavior(tapAction: "a", holdAction: "lctl", ...))
```

This enables conflict detection and UI previews without running Kanata.

## References

- [Kanata Configuration Guide - tap-hold](https://jtroo.github.io/config.html#tap-hold)
- [Home Row Mods Guide](https://precondition.github.io/home-row-mods)

