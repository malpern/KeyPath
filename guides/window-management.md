---
layout: default
title: "Window Management"
description: "Tile, snap, and move windows with keyboard shortcuts — no mouse required"
theme: parchment
header_image: header-window-management.png
permalink: /guides/window-management/
---

# Window Management

Dragging windows with a mouse breaks your flow. KeyPath lets you tile, snap, and move windows with keyboard shortcuts — left half, right half, corners, maximize, center, and switch between displays. All without touching the trackpad.

---

## Quick start: the Window Snapping pack

The fastest way to get window management:

1. Open the **Pack Gallery**
2. Install **Window Snapping**
3. Install **Vim Navigation** if you haven't already (Window Snapping requires it)

Now hold Space, press W to enter the window layer, then press a key to snap:

```
  Hold Space, then W, then:

  ┌─────┬─────┬─────┐
  │  U  │  I  │     │     U = Top-left corner
  │ ◸   │ ◹   │     │     I = Top-right corner
  ├─────┼─────┼─────┤
  │  J  │  K  │  L  │     J = Left half
  │ ◧   │ ☐   │ ◨   │     K = Maximize    L = Right half
  ├─────┼─────┼─────┤
  │  N  │  M  │     │     N = Bottom-left corner
  │ ◺   │ ◻   │     │     M = Bottom-right corner
  └─────┴─────┴─────┘

  Also:
  [ = Previous display    ] = Next display
  , = Previous Space      . = Next Space
```

<!-- Screenshot: Overlay showing window snapping layer with position indicators -->
![Screenshot — Window Snapping layer in the overlay]({{ '/images/help/placeholder-overlay-window-snapping.png' | relative_url }})

Release Space to leave the window layer.

---

## How it works

Window snapping uses macOS Accessibility APIs to move and resize the frontmost window. When you press a position key, KeyPath:

1. Reads the current screen dimensions
2. Calculates the target frame (e.g., left half = left edge, full height, 50% width)
3. Moves and resizes the window via the Accessibility API

This works in every app — no per-app configuration needed.

### Accessibility permission required

The first time you use window snapping, macOS will ask you to grant KeyPath Accessibility permission in **System Settings > Privacy & Security > Accessibility**. Window management won't work without this.

<!-- Screenshot: macOS Accessibility permission prompt -->
![Screenshot — Accessibility permission dialog]({{ '/images/help/placeholder-accessibility-permission.png' | relative_url }})

---

## All window positions

| Key | Position | What it does |
|-----|----------|-------------|
| J | Left half | Window fills the left 50% of the screen |
| L | Right half | Window fills the right 50% |
| K | Maximize | Window fills the entire screen |
| ; | Center | Window centers on screen at current size |
| U | Top-left | Window fills the top-left quarter |
| I | Top-right | Window fills the top-right quarter |
| N | Bottom-left | Window fills the bottom-left quarter |
| M | Bottom-right | Window fills the bottom-right quarter |
| [ | Previous display | Move window to the display on the left |
| ] | Next display | Move window to the display on the right |
| , | Previous Space | Move window to the previous desktop Space |
| . | Next Space | Move window to the next desktop Space |

---

## Using window actions from scripts and tools

You can trigger window positions from Terminal, Shortcuts, or any tool that can open URLs:

```bash
open "keypath://window/left"
open "keypath://window/right"
open "keypath://window/maximize"
open "keypath://window/center"
open "keypath://window/top-left"
open "keypath://window/next-display"
```

This works from Raycast, Alfred, Hammerspoon, or any automation tool. See the [Action URI Reference]({{ '/guides/action-uri-reference/' | relative_url }}) for the full list.

---

## App-Specific Keymaps

Beyond window management, KeyPath can detect which app is in the foreground and switch your key mappings automatically. Different apps get different shortcuts — no manual toggling.

### Creating app-specific rules

1. Open the **Custom Rules** tab in the inspector panel
2. Click **New Rule** (+ button)
3. Select an application from the app picker
4. Add key mappings for that app
5. Click **Save**

```
  ┌─────────────────────────────────────────────────────┐
  │  Custom Rules                                       │
  │                                                     │
  │  ┌────────────────────────────────────────────────┐ │
  │  │  EVERYWHERE (global rules)                     │ │
  │  │  caps_lock ──→ escape                          │ │
  │  └────────────────────────────────────────────────┘ │
  │                                                     │
  │  ┌────────────────────────────────────────────────┐ │
  │  │  🧭 SAFARI                                     │ │
  │  │  h ──→ left    j ──→ down                      │ │
  │  │  k ──→ up      l ──→ right                     │ │
  │  └────────────────────────────────────────────────┘ │
  └─────────────────────────────────────────────────────┘
```

<!-- Screenshot: Custom Rules tab with app-specific rules -->
![Screenshot — App-specific rules in Custom Rules]({{ '/images/help/placeholder-custom-rules-app-specific.png' | relative_url }})

When you switch apps, KeyPath tells Kanata to switch layers automatically. Your keyboard adapts instantly.

### Example: Vim navigation in Safari

A popular setup — use HJKL as arrow keys in Safari for keyboard-driven browsing:

1. Click **New Rule** and select **Safari** as the target app
2. Add mappings: H → Left, J → Down, K → Up, L → Right
3. Click **Save**

Now HJKL works as arrow keys in Safari. Switch to any other app and they go back to normal letters.

---

## Combining with other features

**Quick Launcher + Window Snapping:** Launch an app and immediately tile it. Hold Hyper to launch Safari, then Space → W → L to snap it to the right half.

**Vim Navigation + Window Snapping:** Navigate text with Space → HJKL, then Space → W to tile the window, all without lifting your hands.

**[Running Scripts]({{ '/guides/script-execution/' | relative_url }}) + Window Snapping:** Script complex layouts — open three apps and tile them into a coding workspace with one key.

---

## Troubleshooting

**Window snapping doesn't work:**
- Check that Accessibility permission is granted in System Settings
- Make sure the Window Snapping pack is installed and enabled
- Try the CLI: `open "keypath://window/left"` — if that works, the issue is in the layer activation

**App-specific rules don't activate:**
- Verify the app appears in your rules list
- Check that KeyPath's service is running (green status indicator)
- Try switching away from the app and back
- Check **File > View Logs** for errors

---

## Related guides

- **[Packs & Layers]({{ '/guides/packs/' | relative_url }})** — Browse the full pack catalog
- **[Vim Navigation]({{ '/guides/vim-navigation/' | relative_url }})** — The foundation layer that Window Snapping builds on
- **[Action URI Reference]({{ '/guides/action-uri-reference/' | relative_url }})** — All `keypath://window/` action types
- **[Quick Launcher]({{ '/guides/quick-launcher/' | relative_url }})** — Launch apps with one key
- **[Running Scripts]({{ '/guides/script-execution/' | relative_url }})** — Automate complex workflows
- **[Layers]({{ '/guides/layers/' | relative_url }})** — How layers and activation work

## External resources

- **[Rectangle](https://rectangleapp.com/)** — Dedicated window manager that pairs well with KeyPath shortcuts ↗
- **[Raycast Window Management](https://www.raycast.com/extensions/window-management)** — Raycast's built-in window tiling ↗
