# Tap-Hold & Tap-Dance Support

KeyPath supports advanced key behaviors beyond simple remapping:

- **Tap-Hold (Dual-Role)**: A key that does one thing when tapped, another when held
- **Tap-Dance**: A key that does different things based on tap count (single, double, triple, etc.)

## Quick Start

### Creating a Tap-Hold Key

1. Open **Custom Rules** tab
2. Click **Create Rule**
3. Set your **Start** key (e.g., `1`)
4. Set your **Finish** key (e.g., `2`) — this is the tap action
5. Enable **Hold, Double Tap, etc.** toggle
6. Set **On Hold** (e.g., `3`) — this is what happens when held
7. Choose hold behavior (options appear after entering hold action):
   - **Basic**: Pure timeout-based
   - **Trigger early**: Hold activates on other key press (best for home-row mods)
   - **Quick tap**: Fast taps always register as tap
   - **Custom keys**: Only specific keys trigger early tap
8. Save

### Creating a Tap-Dance Key

1. Open **Custom Rules** tab
2. Click **Create Rule**
3. Set your **Start** key (e.g., `caps`)
4. Set your **Finish** key (e.g., `esc`) — this is the single-tap action
5. Enable **Hold, Double Tap, etc.** toggle
6. Set **Double Tap** (e.g., `caps`)
7. (Optional) Click **Add Tap Step** for triple-tap, quad-tap, etc.
8. Save

> **Note:** Hold and Tap-Dance cannot be used together on the same key. If you try to set one when the other is already configured, a dialog will ask which behavior you want to keep.

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
    public var customTapKeys: [String] // Keys that trigger early tap
}
```

**Kanata Variants (priority order):**
1. `tap-hold-press`: Hold triggers on other key press (`activateHoldOnOtherKey = true`)
2. `tap-hold-release`: Quick-tap / permissive-hold (`quickTap = true`)
3. `tap-hold-release-keys`: Early tap on specific keys (`customTapKeys` non-empty)
4. `tap-hold`: Basic timeout-based (default)

**UI Hold Behavior Options:**
| Option | Description | Kanata Variant |
|--------|-------------|----------------|
| Basic | Hold activates after timeout | `tap-hold` |
| Trigger early | Hold activates when another key is pressed | `tap-hold-press` |
| Quick tap | Fast taps always register as tap | `tap-hold-release` |
| Custom keys | Only specific keys trigger early tap | `tap-hold-release-keys` |

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
// Creates: tap=a, hold=lctl, activateHoldOnOtherKey=true
// Uses tap-hold-press variant (best for home-row mods)
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

;; tap-hold-press (hold on other key press)
(tap-hold-press 200 200 f lmet)

;; tap-hold-release (quick-tap / permissive hold)
(tap-hold-release 200 200 j rsft)

;; tap-hold-release-keys (early tap on specific keys)
(tap-hold-release-keys 200 200 a lctl (s d f))
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
- `(tap-hold ...)`, `(tap-hold-press ...)`, `(tap-hold-release ...)`, `(tap-hold-release-keys ...)`
- `(tap-dance windowMs (action1 action2 ...))`

**Limitations:**
- Only parses KeyPath-generated syntax, not arbitrary Kanata configs
- Does not parse nested behaviors
- Returns `nil` for unrecognized syntax

## UI Components

### Custom Rules Inline Editor

The settings panel now provides a lightweight inline editor for quick key-to-key rules:
- **Input/Output** fields with type-or-select behavior
- **Name/Notes (optional)** for labeling rules

Advanced behavior editing (tap-hold, tap-dance, timing, etc.) should be done in the overlay drawer.

### ConflictResolutionDialog

When Hold and Tap-Dance conflict:
- Visual illustration showing the fork between behaviors
- Current values displayed for both options
- "Keep Hold" / "Switch to Hold" and "Keep Tap" / "Switch to Tap" buttons

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

## Rule Conflict Detection

KeyPath detects when multiple rules map the same input key and shows a warning.

### How It Works

1. **Detection**: When enabling a rule (collection or custom), KeyPath checks for conflicts with other enabled rules
2. **Warning**: If a conflict exists, an orange warning toast appears with a "Basso" sound
3. **Non-blocking**: The action proceeds anyway - conflicts are warnings, not errors
4. **Resolution**: "Last enabled rule wins" - the most recently enabled rule takes precedence in the config

### Types of Conflicts Detected

| Conflict Type | Example |
|---------------|---------|
| Custom Rule vs Custom Rule | Two rules both map `caps` |
| Custom Rule vs Collection | Rule maps `caps`, collection also remaps `caps` |
| Collection vs Collection | Two collections remap the same key on the same layer |
| Activator Conflict | Two collections use the same momentary activator key |

### Warning Message Format

```
⚠️ [Rule Name] conflicts with [Other Rule] on key: [key]. Last enabled rule wins.
```

### Testing

Conflict detection is tested in `RuleCollectionsManagerTests.swift`:
- `testCustomRuleConflictWithCustomRule_WarnsButAllows`
- `testCustomRuleConflictWithCollection_WarnsButAllows`
- `testToggleCustomRule_ConflictWarnsButEnables`
- `testNoConflictWarning_WhenNoOverlap`
- `testDisabledRuleDoesNotConflict`
- `testConflictInfo_ContainsCorrectKeys`

## References

- [Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold)
- [Home Row Mods Guide](https://precondition.github.io/home-row-mods)
- [Kanata tap-dance documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-dance)
