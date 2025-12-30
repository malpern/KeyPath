---
layout: default
title: Tap-Hold & Tap-Dance
description: Advanced key behaviors with tap-hold and tap-dance support
---

# Tap-Hold & Tap-Dance

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
7. Choose hold behavior:
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

## Hold Behavior Options

| Option | Description | Kanata Variant |
|--------|-------------|----------------|
| Basic | Hold activates after timeout | `tap-hold` |
| Trigger early | Hold activates when another key is pressed | `tap-hold-press` |
| Quick tap | Fast taps always register as tap | `tap-hold-release` |
| Custom keys | Only specific keys trigger early tap | `tap-hold-release-keys` |

## Common Use Cases

### Home Row Modifiers

Map your home row keys to modifiers when held:

```
a → a (tap) / Left Control (hold)
s → s (tap) / Left Shift (hold)
d → d (tap) / Left Alt (hold)
f → f (tap) / Left Command (hold)
```

**Settings:**
- Hold behavior: **Trigger early**
- Tap timeout: 200ms
- Hold timeout: 200ms

This allows you to press `a` + `j` quickly and it triggers `Ctrl+J` instead of `aj`.

### Caps Lock Replacement

Replace Caps Lock with Escape on tap, Control on hold:

```
caps → esc (tap) / lctl (hold)
```

**Settings:**
- Hold behavior: **Basic**
- Tap timeout: 200ms

### Space Cadet Shift

Space bar that acts as Space on tap, Shift on hold:

```
spc → spc (tap) / lsft (hold)
```

**Settings:**
- Hold behavior: **Quick tap**
- Tap timeout: 200ms

## Tap-Dance Examples

### Escape / Caps Lock / Control

```
caps → esc (single tap) / caps (double tap) / lctl (triple tap)
```

### Function Key Layer Toggle

```
f1 → f1 (single tap) / layer-toggle function (double tap)
```

## Technical Details

### Kanata Variants

KeyPath generates the appropriate Kanata variant based on your settings:

1. **`tap-hold-press`**: Hold triggers on other key press (`activateHoldOnOtherKey = true`)
2. **`tap-hold-release`**: Quick-tap / permissive-hold (`quickTap = true`)
3. **`tap-hold-release-keys`**: Early tap on specific keys (`customTapKeys` non-empty)
4. **`tap-hold`**: Basic timeout-based (default)

### Timeout Configuration

- **Tap timeout**: Time (ms) before hold activates
- **Hold timeout**: Time (ms) for hold to fully activate

Default is 200ms for both, which works well for most users. Adjust based on your typing speed and preferences.

## Troubleshooting

### Hold activates too quickly

Increase the tap timeout. Try 250ms or 300ms.

### Hold doesn't activate reliably

- Use **Trigger early** for home-row mods
- Decrease hold timeout
- Check for conflicts with other remappings

### Tap-Dance not working

Ensure you've set at least a double-tap action. Single tap alone won't enable tap-dance behavior.

## Advanced Configuration

For power users, you can edit the generated Kanata config directly to fine-tune behavior. See the [Kanata documentation](https://github.com/jtroo/kanata) for advanced options.
