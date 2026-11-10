---
layout: default
title: "Custom Keyboards (QMK)"
description: "Import your QMK keyboard layout so KeyPath's overlay matches your physical keyboard"
theme: parchment
header_image: header-qmk-import.png
permalink: /guides/qmk-import/
---

# Custom Keyboards (QMK)

If you use a custom mechanical keyboard — a split, ortholinear, or compact layout — KeyPath can import your keyboard's physical layout so the overlay matches what you're actually looking at. The overlay shows your keys in the right positions, with the right sizes, in the right arrangement.

KeyPath indexes over 3,700 keyboards from the [QMK firmware](https://qmk.fm/) repository. If your keyboard runs QMK, chances are it's already in the database.

---

## Finding your keyboard

1. Open the KeyPath overlay
2. Click the keyboard layout selector in the header
3. Click **Import QMK Keyboard**
4. Search for your keyboard by name

```
  ┌─────────────────────────────────────────────────┐
  │  Search QMK Keyboards                           │
  │  ┌─────────────────────────────────────────────┐│
  │  │  corne                                      ││
  │  └─────────────────────────────────────────────┘│
  │                                                  │
  │  > Corne (crkbd)                                │
  │    Corne Cherry v3                               │
  │    Corne Chocolate                               │
  │    Corne LP                                      │
  └─────────────────────────────────────────────────┘
```

Select your keyboard and KeyPath downloads the layout definition. The overlay updates immediately to show your physical key arrangement.

---

## Popular keyboards with built-in support

These keyboards ship with pre-built layouts — no import needed, just select from the layout picker:

| Keyboard | Type | Keys |
|----------|------|------|
| Corne (crkbd) | Split | 42 |
| Sofle | Split | 58 |
| Ferris Sweep | Split | 34 |
| HHKB | Compact | 60 |
| Lily58 | Split | 58 |
| Planck | Ortholinear | 48 |

If your keyboard is in this list, you don't need to import — it's already available in the overlay's layout picker.

---

## Importing from a URL

If your keyboard isn't in the search index, you can import directly from a GitHub URL:

1. Find your keyboard's `info.json` on GitHub (in the [QMK firmware repository](https://github.com/qmk/qmk_firmware/tree/master/keyboards))
2. Copy the raw URL
3. In KeyPath, click **Import QMK Keyboard** → **Import from URL**
4. Paste the URL

```
  Example URL:
  https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards/crkbd/info.json
```

KeyPath fetches the layout definition and optionally downloads the default keymap for accurate key labels.

---

## Import options

When importing, you can configure:

| Option | What it does |
|--------|-------------|
| **Keyboard type** | ANSI, ISO, or JIS — determines which key code table to use |
| **Layout variant** | Some keyboards have multiple layouts (e.g., with/without encoder) |
| **Custom name** | Name this layout in the picker (defaults to the QMK keyboard name) |

---

## What gets imported

The import brings in your keyboard's **physical layout** — the positions, sizes, and arrangement of keys. It does not import your QMK keymap (which keys do what). KeyPath handles key behavior through its own [packs]({{ '/guides/packs/' | relative_url }}) and [layers]({{ '/guides/layers/' | relative_url }}) system.

```
  QMK info.json                    KeyPath overlay
  ┌──────────────┐                ┌──────────────┐
  │ Key positions │  ──import──→  │ Physical key  │
  │ Key sizes     │               │ arrangement   │
  │ Key labels    │               │ in the overlay│
  └──────────────┘                └──────────────┘

  Your remaps, layers, and packs work the same
  regardless of which physical layout you use.
```

This means you can switch physical layouts without losing any of your key configurations. Your packs, layers, and custom rules stay the same — only the visual representation changes.

---

## Caching

Imported layouts are cached locally at `~/Library/Caches/KeyPath/qmk/`. If you import the same keyboard again, KeyPath uses the cached version. Delete the cache folder to force a fresh download.

---

## Troubleshooting

**My keyboard isn't in the search:**
- Try different name variations (e.g., "crkbd" vs "corne")
- Import directly from a GitHub URL if the keyboard is in the QMK repository but not the search index

**Layout looks wrong:**
- Check the keyboard type (ANSI/ISO/JIS) — wrong type produces incorrect key codes
- Try a different layout variant if your keyboard has multiple options
- Some custom keyboards have non-standard key arrangements that may need manual adjustment

**Keys are in the wrong position:**
- The import maps QMK grid positions to physical key codes. If your keyboard's `info.json` has unusual coordinates, some keys may appear shifted. Report this as a bug.

---

## Related guides

- **[Works With Your Keyboard]({{ '/guides/keyboard-layouts/' | relative_url }})** — Physical keyboard support overview
- **[Alternative Layouts]({{ '/guides/alternative-layouts/' | relative_url }})** — Colemak, Dvorak, and other keymaps
- **[Packs & Layers]({{ '/guides/packs/' | relative_url }})** — Key behavior is independent of physical layout
- **[Remapping]({{ '/guides/remapping/' | relative_url }})** — Getting started with key remapping
