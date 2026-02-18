---
layout: default
title: Keyboard Concepts for Mac Users
description: Layers, tap-hold, modifiers, and more — explained for people who've never gone beyond System Settings
---

# Keyboard Concepts for Mac Users

If you've never customized a keyboard beyond **System Settings > Keyboard > Modifier Keys**, this page is for you. We'll explain the core ideas behind keyboard remapping using terminology you already know from macOS.

---

## What keyboard remapping actually does

You already know you can swap Caps Lock and Control in System Settings. Keyboard remapping is the same idea, but far more powerful:

- Remap *any* key to *any* other key (not just modifiers)
- Make a single key do different things depending on *how* you press it
- Create entirely separate keyboard layouts you can switch between
- Set up app-specific shortcuts that only activate in certain applications

KeyPath uses [Kanata](https://github.com/jtroo/kanata) as its engine — a purpose-built keyboard remapping tool — and wraps it in a native Mac interface so you don't have to edit config files.

---

## Keys, modifiers, and shortcuts

You already use these every day on your Mac:

| macOS name | Symbol | What it does |
|---|---|---|
| **Command** | ⌘ | The primary modifier — ⌘C to copy, ⌘V to paste |
| **Option** | ⌥ | Secondary modifier — special characters, alternate actions |
| **Control** | ⌃ | Used in Terminal, Emacs-style shortcuts |
| **Shift** | ⇧ | Uppercase letters, alternate toolbar actions |

A **shortcut** is a modifier held together with another key: ⌘S to save, ⌥⌘Esc to force quit.

In keyboard remapping, we can make *any* key act as a modifier — including your home row letter keys.

---

## Layers

Think of layers like having multiple keyboards stacked on top of each other. You're always typing on one layer, and you can switch between them.

```
  Layer 0 (Base)         Layer 1 (Navigation)
  ┌───┬───┬───┬───┐     ┌───┬───┬───┬───┐
  │ Q │ W │ E │ R │     │   │   │   │   │
  ├───┼───┼───┼───┤     ├───┼───┼───┼───┤
  │ A │ S │ D │ F │     │ ← │ ↓ │ ↑ │ → │
  ├───┼───┼───┼───┤     ├───┼───┼───┼───┤
  │ Z │ X │ C │ V │     │   │   │   │   │
  └───┴───┴───┴───┘     └───┴───┴───┴───┘

  Hold a key to switch → arrows on the home row!
```

**You already use layers on your Mac** — holding Shift gives you a different "layer" of characters (uppercase letters, symbols like ! @ # $). Keyboard remapping just lets you create as many additional layers as you want.

Common uses:
- **Navigation layer** — arrow keys, Page Up/Down, Home/End on the home row
- **Number layer** — a numpad layout under your right hand
- **Symbol layer** — brackets, braces, and programming symbols within easy reach

---

## Tap-hold (dual-role keys)

This is the most powerful concept in keyboard remapping: **one key, two jobs**.

- **Tap** the key quickly → it types the letter
- **Hold** the key down → it acts as a modifier

```
  ┌─────────┐
  │    F    │   Tap  → types "f"
  │   ⌘     │   Hold → acts as Command
  └─────────┘
```

For example, you could make the F key type "f" when tapped but act as Command when held. Press and release F quickly: you get the letter f. Hold F and press C: you get ⌘C (Copy).

This is how [home row mods]({{ '/guides/home-row-mods' | relative_url }}) work — your home row letter keys double as modifiers, so you never have to reach for Command, Option, Control, or Shift.

KeyPath gives you sliders and visual controls to fine-tune the timing so the tap/hold split feels natural for your typing speed. See the [Tap-Hold guide]({{ '/guides/tap-hold' | relative_url }}) for all the details.

---

## Tap-dance

Tap-dance takes the dual-role idea further: **different actions based on how many times you tap**.

```
  Caps Lock:
    1 tap  → Escape
    2 taps → Caps Lock (the original function)
    3 taps → Control
```

This is great for keys you rarely use — you can pack multiple functions into a single key without adding complexity to your everyday typing.

---

## Home row mods

Home row mods combine tap-hold with your home row keys (A S D F / J K L ;) to turn them into modifiers when held:

```
  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
  │  A  │ │  S  │ │  D  │ │  F  │     │  J  │ │  K  │ │  L  │ │  ;  │
  │ ⇧   │ │ ⌃   │ │ ⌥   │ │ ⌘   │     │ ⌘   │ │ ⌥   │ │ ⌃   │ │ ⇧   │
  └─────┘ └─────┘ └─────┘ └─────┘     └─────┘ └─────┘ └─────┘ └─────┘
              Tap for letters, hold for modifiers
```

This is the most popular advanced keyboard technique. Your fingers never leave the home row to hit modifiers — everything is right under your fingertips.

KeyPath includes built-in support for home row mods with split-hand detection and per-finger timing to make them feel reliable from day one.

Read the full [Home Row Mods guide]({{ '/guides/home-row-mods' | relative_url }}) to get started.

---

## Where to go next

- **[Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }})** — Create a simple remap to see how KeyPath works
- **[Home Row Mods]({{ '/guides/home-row-mods' | relative_url }})** — The most popular advanced technique
- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})** — All the details on dual-role keys
- **[Back to Docs]({{ '/docs' | relative_url }})** — See all available guides
