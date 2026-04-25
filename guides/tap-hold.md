---
layout: default
title: "One Key, Multiple Actions"
description: "Advanced key behaviors with tap-hold and tap-dance support"
theme: parchment
header_image: header-tap-hold.png
permalink: /guides/tap-hold/
---


# One Key, Multiple Actions

A standard keyboard gives you about 80 keys, and each one does exactly one thing. That's limiting — you run out of convenient shortcuts fast, especially if you want to launch apps, navigate, and use modifiers without leaving the home row.

KeyPath lets a single key do different things depending on *how* you press it:

- **Tap-Hold**: Tap for one action, hold for another — like Caps Lock that sends Escape on tap but activates shortcuts on hold
- **Tap-Dance**: Different actions for single tap, double tap, triple tap — like a double-click but for any key

These dual-role keys are the foundation of everything else in KeyPath: [home row modifiers]({{ '/guides/home-row-mods/' | relative_url }}), [app launching]({{ '/guides/action-uri/' | relative_url }}), navigation layers, and more.

If you're new to these ideas, start with the [Keyboard Concepts]({{ '/guides/concepts/' | relative_url }}) page for a beginner-friendly overview.

---

## Quick Start

### Creating a Tap-Hold Key

1. Open the **Custom Rules** tab in the inspector panel
2. Click **New Rule** (+ button)
3. Set your **Start** key and **Finish** key (tap action)
4. Enable the **Hold, Double Tap, etc.** toggle
5. Set **On Hold** — this is what happens when held
6. Choose hold behavior
7. Save


![Screenshot]({{ '/images/help/tap-hold-custom-rules-tab.png' | relative_url }})
Screenshot — Custom Rules tab with new rule form:
```
  ┌─────────────────────────────────────────────────────┐
  │  Custom Rules                                       │
  │                                                     │
  │  ┌────────────────────────────────────────────────┐ │
  │  │  EVERYWHERE (global rules)                     │ │
  │  │                                                │ │
  │  │  caps_lock ──→ escape                          │ │
  │  │  a (hold) ──→ left_shift                       │ │
  │  │  f (hold) ──→ left_command                     │ │
  │  └────────────────────────────────────────────────┘ │
  │                                                     │
  │  ┌────────────────────────────────────────────────┐ │
  │  │  🧭 SAFARI (app-specific rules)                │ │
  │  │                                                │ │
  │  │  h ──→ left_arrow                              │ │
  │  │  j ──→ down_arrow                              │ │
  │  │  k ──→ up_arrow                                │ │
  │  │  l ──→ right_arrow                             │ │
  │  └────────────────────────────────────────────────┘ │
  │                                                     │
  │  [ ↺ Reset ]                     [ + New Rule ]     │
  └─────────────────────────────────────────────────────┘
```


![Screenshot]({{ '/images/help/tap-hold-rule-editor.png' | relative_url }})
Screenshot — Rule editor with hold behavior options:
```
  ┌─────────────────────────────────────────────────────┐
  │  New Rule                                           │
  │                                                     │
  │  Start key:    [ caps_lock      ▾ ]                 │
  │  Finish key:   [ escape         ▾ ]  (tap action)   │
  │                                                     │
  │  ┌ Hold, Double Tap, etc. ─────────────── [ON] ──┐ │
  │  │                                                │ │
  │  │  On Hold:   [ left_control   ▾ ]               │ │
  │  │                                                │ │
  │  │  Hold Behavior:                                │ │
  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │ │
  │  │  │  Basic   │ │ Trigger  │ │  Quick   │       │ │
  │  │  │          │ │  early   │ │   tap    │       │ │
  │  │  └──────────┘ └──────────┘ └──────────┘       │ │
  │  │                                                │ │
  │  │  Tap timeout:   [ 200 ms ]                     │ │
  │  │  Hold timeout:  [ 200 ms ]                     │ │
  │  └────────────────────────────────────────────────┘ │
  │                                                     │
  │                              [ Cancel ]  [ Save ]   │
  └─────────────────────────────────────────────────────┘
```

### Creating a Tap-Dance Key

1. Open the **Custom Rules** tab in the inspector panel
2. Click **New Rule** (+ button)
3. Set your **Start** key (e.g., `caps`)
4. Set your **Finish** key (e.g., `esc`) — this is the single-tap action
5. Enable **Hold, Double Tap, etc.** toggle
6. Set **Double Tap** (e.g., `caps`)
7. (Optional) Click **Add Tap Step** for triple-tap, quad-tap, etc.
8. Save

> **Note:** Hold and Tap-Dance cannot be used together on the same key. If you try to set one when the other is already configured, a dialog will ask which behavior you want to keep.

---

## Hold Behavior Options

| Option | Description |
|--------|-------------|
| Basic | Hold activates after timeout |
| Trigger early | Hold activates when another key is pressed |
| Quick tap | Fast taps always register as tap |
| Custom keys | Only specific keys trigger early tap |

---

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

---

## Tap-Dance Examples

### Escape / Caps Lock / Control

```
caps → esc (single tap) / caps (double tap) / lctl (triple tap)
```

### Function Key Layer Toggle

```
f1 → f1 (single tap) / layer-toggle function (double tap)
```

---

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

---

## Troubleshooting

### Hold activates too quickly

Increase the tap timeout. Try 250ms or 300ms.

### Hold doesn't activate reliably

- Use **Trigger early** for home-row mods
- Decrease hold timeout
- Check for conflicts with other remappings

### Tap-Dance not working

Ensure you've set at least a double-tap action. Single tap alone won't enable tap-dance behavior.

---

## Advanced Configuration

For power users, you can edit the generated Kanata config directly to fine-tune behavior. See the [Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold) for all available options.

---

## Next Steps

- **[Shortcuts Without Reaching]({{ '/guides/home-row-mods/' | relative_url }})** — The most popular use of tap-hold
- **[What You Can Build]({{ '/guides/use-cases/' | relative_url }})** — See tap-hold in action: Hyper key, navigation layers, combined setups
- **[Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})** — Background on layers, modifiers, and dual-role keys
- **[Launching Apps]({{ '/guides/action-uri/' | relative_url }})** — Trigger actions from your keyboard config
- **[Alternative Layouts]({{ '/guides/alternative-layouts/' | relative_url }})** — Tap-hold works with any layout
- **[Switching from Karabiner?]({{ '/migration/karabiner-users/' | relative_url }})** — See how Karabiner's `to_if_alone` maps to Kanata tap-hold
- **[Back to Docs](https://keypath-app.com/docs)**

## External resources

- **[Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold)** — Full reference for all tap-hold variants ↗
- **[The Home Row Mods Guide (Precondition)](https://precondition.github.io/home-row-mods)** — Community deep dive on tap-hold for home row mods ↗
- **[Pascal Getreuer's home row mods analysis](https://getreuer.info/posts/keyboards/home-row-mods/)** — Technical analysis of tap-hold timing and anti-misfire strategies ↗
- **[QMK tap-hold documentation](https://docs.qmk.fm/tap_hold)** — Firmware perspective on the same concepts (useful for understanding the theory) ↗
- **[Kanata GitHub Discussions](https://github.com/jtroo/kanata/discussions)** — Community Q&A on tap-hold tuning ↗
