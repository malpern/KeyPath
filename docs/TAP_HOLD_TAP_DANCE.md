# Tap-Hold & Tap-Dance Support

KeyPath supports advanced key behaviors beyond simple remapping:

- **Tap-Hold (Dual-Role)**: A key that does one thing when tapped, another when held
- **Tap-Dance**: A key that does different things based on tap count (single, double, triple, etc.)

## Quick Start

### Creating a Tap-Hold Key

1. Open **Custom Rules** tab
2. Click **Create Rule**
3. Set your input key (e.g., `a`)
4. Click the **Advanced** tab (segmented control)
5. Select **Tap / Hold**
6. Set:
   - **Tap**: `a` (what happens on quick tap)
   - **Hold**: `lctl` (what happens when held)
7. Save

### Creating a Tap-Dance Key

1. Open **Custom Rules** tab
2. Click **Create Rule**
3. Set your input key (e.g., `caps`)
4. Click the **Advanced** tab
5. Select **Tap Dance**
6. Add steps:
   - **Single tap**: `esc`
   - **Double tap**: `caps`
7. Save

## Data Model

### MappingBehavior

The `MappingBehavior` enum represents advanced key behaviors:

```swift
public enum MappingBehavior: Codable, Equatable, Sendable {
    case dualRole(DualRoleBehavior)
    case tapDance(TapDanceBehavior)
}
```

### DualRoleBehavior

Settings for tap-hold keys:

```swift
public struct DualRoleBehavior: Codable, Equatable, Sendable {
    public var tapAction: String      // Action on tap (e.g., "a")
    public var holdAction: String     // Action on hold (e.g., "lctl")
    public var tapTimeout: Int        // ms before hold activates (default: 200)
    public var holdTimeout: Int       // ms for hold to fully activate (default: 200)
    public var activateHoldOnOtherKey: Bool  // Hold triggers on other key press
    public var quickTap: Bool         // Fast taps always register as tap
}
```

**Kanata Variants:**
- `tap-hold`: Basic timeout-based (neither flag set)
- `tap-hold-press`: Hold triggers on other key press (`activateHoldOnOtherKey = true`)
- `tap-hold-release`: Quick-tap / permissive-hold (`quickTap = true`)

> **Note:** If both `activateHoldOnOtherKey` and `quickTap` are true, `activateHoldOnOtherKey` takes precedence.

### TapDanceBehavior

Settings for tap-dance keys:

```swift
public struct TapDanceBehavior: Codable, Equatable, Sendable {
    public var windowMs: Int          // Time window to register taps (default: 200)
    public var steps: [TapDanceStep]  // Actions for each tap count
}

public struct TapDanceStep: Codable, Equatable, Sendable {
    public var label: String          // Human-readable label
    public var action: String         // Key or action to perform
}
```

## Factory Methods

### Home Row Mods

For the common home-row modifier pattern:

```swift
let homeRowA = DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl")
// Creates: tap=a, hold=lctl, activateHoldOnOtherKey=true, quickTap=true
```

### Two-Step Tap-Dance

For simple single/double tap patterns:

```swift
let capsEsc = TapDanceBehavior.twoStep(singleTap: "esc", doubleTap: "caps")
// Creates: window=200ms, steps=[esc, caps]
```

## Generated Kanata Syntax

### Tap-Hold Examples

```lisp
;; Basic tap-hold (timeout-based)
(tap-hold 200 200 a lctl)

;; tap-hold-press (hold on other key)
(tap-hold-press 200 200 f lmet)

;; tap-hold-release (quick-tap)
(tap-hold-release 200 200 j rsft)
```

### Tap-Dance Examples

```lisp
;; Two-step tap-dance
(tap-dance 200 (esc caps))

;; Three-step tap-dance
(tap-dance 150 (spc ret tab))
```

## Validation

Both behavior types have an `isValid` property:

```swift
// DualRoleBehavior.isValid
// - tapAction must not be empty
// - holdAction must not be empty
// - tapTimeout must be > 0
// - holdTimeout must be > 0

// TapDanceBehavior.isValid
// - windowMs must be > 0
// - At least one step with non-empty action
```

## Parsing (Round-Trip Support)

`KanataBehaviorParser` can parse KeyPath-generated Kanata syntax back into `MappingBehavior`:

```swift
let behavior = KanataBehaviorParser.parse("(tap-hold-press 200 200 a lctl)")
// Returns: .dualRole(DualRoleBehavior(tapAction: "a", holdAction: "lctl", ...))
```

**Supported syntax:**
- `(tap-hold ...)`, `(tap-hold-press ...)`, `(tap-hold-release ...)`
- `(tap-dance windowMs (action1 action2 ...))`

**Limitations:**
- Only parses KeyPath-generated syntax, not arbitrary Kanata configs
- Does not parse nested behaviors
- Returns `nil` for unrecognized syntax

## UI Components

### MappingBehaviorEditor

The main editor component with:
- **Simple/Advanced** segmented control
- **Tap/Hold** or **Tap Dance** picker in Advanced mode
- State grid for actions
- Timing controls with per-state overrides
- Live Kanata syntax preview

## Future: Side-Channel Telemetry

> **Status:** Not yet implemented

A future enhancement will allow Kanata to report how each key resolved (tap vs. hold) back to KeyPath via the TCP side-channel. This will enable:

- Visual feedback showing which action was triggered
- Analytics on tap/hold timing patterns
- Adaptive timeout suggestions

### Proposed Schema

```json
{
  "TapHoldResolution": {
    "key": "a",
    "resolution": "tap",  // or "hold"
    "duration_ms": 150,
    "timestamp": 1234567890
  }
}
```

This requires Kanata to emit resolution events, which is not currently supported.

## References

- [Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold)
- [Home Row Mods Guide](https://precondition.github.io/home-row-mods)
- [Kanata tap-dance documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-dance)
