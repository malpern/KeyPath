---
layout: default
title: "Arrow Keys at Full Speed"
description: "Arrow keys and delete repeat 3x faster while regular typing stays steady — no accidental repeats."
theme: parchment
header_image: header-key-repeat-control.png
permalink: /guides/key-repeat-control/
---


# Arrow Keys and Delete at Full Speed

Your arrow keys move through text at the same sluggish speed as every other key. Holding → to get across a line takes forever. Holding Delete to clear a word feels like watching paint dry. Fast Navigation makes navigation and deletion keys repeat 3× faster while keeping regular typing steady — no accidental repeated characters.

---

## What You Get

Enable **Fast Navigation** and you get per-key repeat speed control. KeyPath
describes speed in repeats per second, so higher values always feel faster:

- **Arrow keys** (←→↑↓) — start repeating in 150 ms, then repeat 50 times per second (20 ms interval)
- **Delete** (⌫) — starts in 210 ms, then repeats 50 times per second
- **Forward Delete** — starts in 210 ms, then repeats 50 times per second
- **Regular keys** (letters, numbers) — start after 500 ms, then repeat about 33 times per second (30 ms interval)

The result: hold an arrow key and it flies. Hold a letter and it stays steady.

---

## Enabling It

Fast Navigation is **enabled by default** for new installations. To check or toggle:

1. Open KeyPath and click the gear icon to open the inspector panel
2. Go to the **Rules** tab
3. Find **Fast Navigation** (hare icon)
4. Toggle on/off or choose a preset

---

## Presets

Three named presets to get started quickly:

| Preset | Repeat start delay | Repeat speed | Feel |
|--------|--------------------|--------------|------|
| **Balanced** (default) | 150 ms | 50 repeats/sec (20 ms interval) | Fast arrows, steady text |
| **Fast Navigation** | 120 ms | 67 repeats/sec (15 ms interval) | Maximum speed for power users |
| **Careful** | 300 ms | 40 repeats/sec (25 ms interval) | Slower, fewer accidental repeats |

Select a preset card in the pack detail view. You can further customize in Settings.

---

## Custom Settings

Click **Settings…** in the pack detail view to fine-tune:

### Global defaults
- **Repeat start delay** — how long you hold a key before repeating starts. Moving right starts later.
- **Repeat speed** — how quickly the key repeats after it starts. Moving right is always faster.
- **Interval** — the equivalent milliseconds between repeats, shown as a secondary technical detail.

### Per-key overrides
- **Arrow keys** — toggle fast arrows on/off, then adjust start delay and repeat speed independently
- **Delete** — toggle fast delete, adjust separately
- **Forward Delete** — toggle and adjust
- **Custom keys** — add any key to the override list with its own speed settings

For example, **50 repeats/sec** and a **20 ms interval** describe the same
setting. KeyPath stores the interval because that is what the keyboard engine
uses, while the main control shows repeats per second because it matches the
way speed feels.

---

## The Test Area

The pack detail view includes a live test area: a text field where you can hold arrow keys and delete to *feel* the difference. Try holding an arrow, then holding a letter — the speed difference is immediately obvious.

---

## How It Works

KeyPath uses Kanata's `defcfg` key-repeat settings to set different speeds for different keys. Instead of the system-wide repeat rate (which applies uniformly to all keys), KeyPath configures:

1. A **slow global rate** for regular typing keys (prevents accidental repeats)
2. A **fast override** for navigation and deletion keys (makes cursor movement instant)

This is not a hack — it's using the keyboard firmware's built-in repeat control, just configured per-key instead of globally.

---

## Tips

- **Pair with Vim Navigation** — fast arrow keys make the H/J/K/L navigation layer even snappier for long-distance moves
- **Adjust delete carefully** — too fast and you'll overshoot. The 210 ms start delay gives you time to lift your finger.
- **The test area is your friend** — adjust values, then immediately feel the result in the test text field
- Works standalone — no dependency on any other pack

---

## Troubleshooting

### Arrow keys don't feel faster

1. Verify Fast Navigation is **enabled** (check the Rules tab)
2. Make sure KeyPath's service is running (green indicator)
3. Check that System Settings → Keyboard → Key Repeat hasn't overridden things — KeyPath's settings take precedence when the service is active

### I'm getting accidental repeated characters when typing

The global repeat start delay (500 ms) should prevent this. If you've lowered it:
1. Go to Settings in the pack detail
2. Increase the global repeat start delay back toward 500 ms
3. Only lower the per-key overrides for arrow/delete keys

### I want different speeds for up/down vs. left/right

Currently all four arrow keys share the same override settings. Per-direction tuning is a potential future enhancement.

---

## Next Steps

- **[Navigate Text Like a Keyboard Ninja]({{ '/guides/vim-navigation/' | relative_url }})** — Combine fast arrows with home-row navigation
- **[Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})** — Background on how KeyPath controls key behavior
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**
