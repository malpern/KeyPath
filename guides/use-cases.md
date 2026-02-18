---
layout: default
title: What You Can Build
description: Concrete examples of what KeyPath can do — from simple remaps to full keyboard workflows
---

# What You Can Build

KeyPath can do a lot more than remap Caps Lock. Here are real setups people use every day, from simple to advanced. Each one is built into KeyPath or achievable through the rule editor.

New to these ideas? Read [Keyboard Concepts]({{ '/guides/concepts' | relative_url }}) first.

---

## The Hyper Key: Your Personal Shortcut Layer

The most popular KeyPath setup. Turn Caps Lock into a dual-role key:

- **Tap** Caps Lock → Escape (great for Vim users, or just dismissing dialogs)
- **Hold** Caps Lock → Hyper (Control + Option + Command + Shift)

```
  ┌──────────┐
  │ Caps Lock│   Tap  → Escape
  │  HYPER   │   Hold → ⌃⌥⌘⇧ (all four modifiers)
  └──────────┘
```

Now hold Caps Lock and press any letter to trigger a unique shortcut that will never conflict with any app:

```
  Hyper + S → Open Safari
  Hyper + T → Open Terminal
  Hyper + F → Open Finder
  Hyper + M → Open Messages
  Hyper + 1 → Open GitHub
  Hyper + 2 → Open Google
```

KeyPath's launcher lets you bind any Hyper combo to open apps, URLs, files, or folders. One key hold + one letter = instant access to anything.

```
  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
  │   │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ 8 │   │
  │   │ ↓ │ ↓ │ ↓ │ ↓ │   │   │   │   │   │
  │   │git│goo│not│S/O│   │   │   │   │   │
  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
  │   │   │   │ E │ R │   │   │ U │ I │ O │
  │   │   │   │ ↓ │ ↓ │   │   │ ↓ │ ↓ │ ↓ │
  │   │   │   │Mail│Red│   │   │Mus│Cla│Obs│
  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
  │HYP│ A │ S │ D │ F │ G │ H │ J │ K │ L │
  │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │ ↓ │
  │CAP│Cal│Saf│Trm│Fnd│GPT│YT │ 𝕏 │Msg│Lin│
  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
  │   │ Z │ X │ C │ V │   │ N │   │   │   │
  │   │ ↓ │ ↓ │ ↓ │ ↓ │   │ ↓ │   │   │   │
  │   │Zoom│Slk│Dis│VSC│   │Not│   │   │   │
  └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘

  Hold Caps Lock (Hyper) + any key → launch that app
```

**How to set it up:** Enable the "Caps Lock Remap" pre-built rule, then add launcher bindings in the Launcher tab.

---

## Navigation Layer with Meh

Use the Meh key (Control + Option + Shift) to activate a navigation layer. Hold one key, and your right hand becomes arrow keys, Page Up/Down, and Home/End:

```
  Hold Meh activator...

  Right hand becomes:
  ┌─────┬─────┬─────┬─────┐
  │     │     │     │     │
  ├─────┼─────┼─────┼─────┤
  │  ←  │  ↓  │  ↑  │  →  │
  ├─────┼─────┼─────┼─────┤
  │Home │PgDn │PgUp │ End │
  └─────┴─────┴─────┴─────┘

  Navigate without leaving the home row.
  No more reaching for arrow keys.
```

This is especially powerful on a MacBook where the arrow keys are small and awkward.

**How to set it up:** Create a custom rule with a tap-hold key that activates a navigation layer on hold.

---

## Home Row Mods

Put Shift, Control, Option, and Command right under your fingers:

```
  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
  │  A  │ │  S  │ │  D  │ │  F  │     │  J  │ │  K  │ │  L  │ │  ;  │
  │ ⇧   │ │ ⌃   │ │ ⌥   │ │ ⌘   │     │ ⌘   │ │ ⌥   │ │ ⌃   │ │ ⇧   │
  └─────┘ └─────┘ └─────┘ └─────┘     └─────┘ └─────┘ └─────┘ └─────┘
```

Hold F + press C = ⌘C (Copy). Hold A + press Tab = ⇧Tab. No reaching, no contortion.

KeyPath's split-hand detection and per-finger timing make this work reliably — fast typing produces letters, deliberate chords produce modifiers.

**How to set it up:** Enable the "Home Row Mods" pre-built rule. See the full [Home Row Mods guide]({{ '/guides/home-row-mods' | relative_url }}).

---

## Window Tiling

Snap windows to halves, thirds, or corners using keyboard shortcuts:

```
  Hyper + H → Snap window left half
  Hyper + L → Snap window right half
  Hyper + K → Maximize window
  Hyper + J → Center window

  Hyper + U → Top-left quarter
  Hyper + I → Top-right quarter
  Hyper + N → Bottom-left quarter
  Hyper + M → Bottom-right quarter
```

```
  ┌───────────┬───────────┐
  │           │           │
  │  Hyper+H  │  Hyper+L  │
  │   (left)  │  (right)  │
  │           │           │
  └───────────┴───────────┘

  ┌─────┬─────┐
  │ U   │  I  │     Four corners
  ├─────┼─────┤     with Hyper +
  │ N   │  M  │     home row keys
  └─────┴─────┘
```

KeyPath uses the [Action URI system]({{ '/guides/action-uri' | relative_url }}) to control windows directly from your keyboard config.

**How to set it up:** Enable the "Window Snapping" pre-built rule, or create custom Action URI bindings.

---

## Vim Navigation Everywhere

Use HJKL as arrow keys system-wide, or only in specific apps:

```
  Meh + H → Left
  Meh + J → Down
  Meh + K → Up
  Meh + L → Right
```

Or go further with app-specific keymaps — Vim-style navigation that only activates in Safari, Finder, or any app you choose:

```
  In Safari:              In other apps:
  ┌───┬───┬───┬───┐      ┌───┬───┬───┬───┐
  │   │   │   │   │      │   │   │   │   │
  ├───┼───┼───┼───┤      ├───┼───┼───┼───┤
  │ ← │ ↓ │ ↑ │ → │      │ H │ J │ K │ L │
  ├───┼───┼───┼───┤      ├───┼───┼───┼───┤
  │   │   │   │   │      │   │   │   │   │
  └───┴───┴───┴───┘      └───┴───┴───┴───┘
  (HJKL = arrows)        (HJKL = normal letters)
```

KeyPath detects which app is active and switches layers automatically via TCP.

**How to set it up:** Add Safari (or any app) in the App-Specific Rules tab, then configure HJKL mappings. See the [Window Management guide]({{ '/guides/window-management' | relative_url }}).

---

## Leader Key Sequences

Press a leader key, then type a short mnemonic to trigger an action — like Vim's leader key but for your whole Mac:

```
  Leader → S → M  → Open Messages
  Leader → S → S  → Open Safari
  Leader → S → T  → Open Terminal

  Leader → G → H  → Open GitHub
  Leader → G → M  → Open Gmail

  Leader → W → L  → Snap window left
  Leader → W → R  → Snap window right
```

Sequences are memorable (S for "switch app", G for "go to", W for "window") and you'll never run out of combinations.

**How to set it up:** Create sequence rules in the Custom Rules tab, or define them in your Kanata config using `defseq`.

---

## Quick Caps Lock Replacement

The simplest and most popular remap — no layers, no complexity:

```
  Caps Lock → Escape
```

One rule, done. Useful for Vim users, or anyone who never uses Caps Lock but constantly needs Escape.

Want more? Make it dual-role:

```
  Caps Lock:
    Tap   → Escape
    Hold  → Control
```

Now Caps Lock does two useful things instead of one useless thing.

**How to set it up:** Enable the "Caps Lock Remap" pre-built rule and choose your preferred behavior.

---

## Combining Techniques

The real power comes from combining these ideas. Here's a complete setup:

```
  Caps Lock → Escape (tap) / Hyper (hold)
  Home row  → Letters (tap) / Modifiers (hold)
  Hyper + letter → Launch apps
  Hyper + HJKL  → Window tiling
  Meh + HJKL    → Arrow navigation
  Leader → ...  → Everything else
```

Your fingers never leave the home row. Apps launch instantly. Windows tile with a keystroke. Every shortcut is one fluid motion.

Start with one technique, get comfortable, then add the next. There's no rush.

---

## Where to go next

- **[Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }})** — Get started with a simple remap
- **[Home Row Mods]({{ '/guides/home-row-mods' | relative_url }})** — Deep dive on the most popular technique
- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})** — Fine-tune your dual-role keys
- **[Action URIs]({{ '/guides/action-uri' | relative_url }})** — Launch apps, URLs, and workflows from your keyboard
- **[Window Management]({{ '/guides/window-management' | relative_url }})** — App-specific keymaps and window tiling
- **[Back to Docs]({{ '/docs' | relative_url }})**
