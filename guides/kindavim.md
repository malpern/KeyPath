---
layout: default
title: "Full Vim Modes on macOS"
description: "Use KindaVim for real Vim modes system-wide, with KeyPath leader-key shortcuts for Insert mode"
theme: parchment
header_image: header-use-cases.png
permalink: /guides/kindavim/
---


# Full Vim Modes on macOS

Keyboard shortcuts can only approximate Vim. You can map `h` to `←` and `d` to delete, but you can't do `d3w` (delete three words) or `ci"` (change inside quotes) — those need real Vim state. KindaVim is a macOS app that provides genuine Vim modes system-wide. KeyPath's KindaVim collection bridges the gap: KindaVim handles full Normal and Visual modes, while KeyPath gives you leader-key navigation shortcuts for when you're typing.

New to keyboard customization? Read [Keyboard Concepts]({{ '/guides/concepts/' | relative_url }}) first for background on layers and dual-role keys.

---

## Why Not Just Use KeyPath's Vim Collection?

KeyPath's built-in Vim collection maps keys to macOS shortcuts — `h` becomes `←`, `d` becomes Option+Delete, and so on. It's a solid shortcut layer, but macOS has no concept of modes, so it can't do:

- **Mode switching** — there's no Normal mode to escape into
- **Operators + motions** — `d3w`, `ct.`, `yap` require Vim-level parsing
- **Text objects** — `ci"`, `da(`, `vis` for inner sentence need actual Vim state

If you're happy with hjkl arrows and basic shortcuts, the Vim collection is all you need. But if you miss real Vim, read on.

---

## What KindaVim Adds

KindaVim is a third-party macOS app that adds genuine Vim modes to every text field on your Mac — Mail, Notes, Slack, your browser's address bar, everywhere:

- **Normal mode** — navigate, delete, yank, paste with real Vim commands
- **Visual mode** — select text with motions and text objects
- **Operators + motions** — `d3w`, `ct.`, `yap` all work as expected
- **Text objects** — `ci"`, `da(`, `vis` for inner sentence, and more

Press `Escape` to enter Normal mode, `i`/`a`/`o` to return to Insert mode — just like real Vim.

---

## How They Work Together

KindaVim and KeyPath each handle what they're best at:

| When you're in... | What happens |
|-------------------|-------------|
| **Normal mode** (KindaVim active) | KindaVim handles everything — operators, motions, text objects. KeyPath stays out of the way. |
| **Insert mode** (typing normally) | Hold Leader key → KeyPath's nav layer activates with vim-flavored shortcuts for quick jumps without leaving Insert mode. |

The KindaVim collection includes all the Vim collection shortcuts plus word motions (`w`, `b`, `e`) and paragraph jumps (`{`, `}`) that Vim users expect.

---

## Setting It Up

### 1. Install KindaVim

Download KindaVim from [kindavim.app ↗](https://kindavim.app) if you haven't already. KeyPath detects whether it's installed and shows a status banner.

### 2. Enable the KindaVim Collection

Open KeyPath and find **KindaVim** in the rules list. Toggle it on and expand to see your shortcuts:

Screenshot — KindaVim collection expanded in the rules list:
```
  ┌─────────────────────────────────────────────────────┐
  │  KindaVim                                 [  ON  ]  │
  │                                                     │
  │  ┌───────────────────────────────────────────────┐  │
  │  │  ✓  KindaVim is installed                     │  │
  │  └───────────────────────────────────────────────┘  │
  │                                                     │
  │  KindaVim brings real Vim modes to every macOS      │
  │  app. This collection adds leader-key shortcuts     │
  │  for quick access when in Insert mode.              │
  │                                                     │
  │  ┌──────────────────┐  ┌──────────────────┐        │
  │  │   Movement       │  │   Word Motion    │        │
  │  │   h ← j ↓ k ↑ l →  │   w → word fwd   │        │
  │  │   0 line start   │  │   b ← word back  │        │
  │  │   $ line end     │  │   e end of word  │        │
  │  └──────────────────┘  └──────────────────┘        │
  │                                                     │
  │  ┌──────────────────┐  ┌──────────────────┐        │
  │  │   Editing        │  │   Search         │        │
  │  │   x delete char  │  │   / find         │        │
  │  │   d delete word  │  │   n next match   │        │
  │  │   u undo         │  │                  │        │
  │  │   r redo         │  │                  │        │
  │  └──────────────────┘  └──────────────────┘        │
  │                                                     │
  │  ┌──────────────────┐                              │
  │  │   Clipboard      │                              │
  │  │   y yank         │                              │
  │  │   p put          │                              │
  │  └──────────────────┘                              │
  │                                                     │
  │  💡 KindaVim provides full Vim modes. This          │
  │     collection adds leader-key shortcuts.           │
  └─────────────────────────────────────────────────────┘
```

If KindaVim is not installed, you'll see an amber banner with a **Download KindaVim** button instead.

### 3. Handle the Vim Conflict

The KindaVim and Vim collections target the same keys on the navigation layer. If both are enabled, KeyPath shows a conflict dialog — pick KindaVim and the Vim collection turns off automatically. You can always switch back.

---

## More Shortcuts at Your Fingertips

The KindaVim collection includes everything from the Vim collection, plus word and paragraph motions:

| Key | What it does | Why it matters |
|-----|-------------|----------------|
| w | Jump forward one word | Edit at word speed, not character speed |
| b | Jump back one word | Same — backwards |
| e | Jump to end of word | Land precisely at word boundaries |
| { | Paragraph up | Skip entire paragraphs in long documents |
| } | Paragraph down | Same — downwards |

All original Vim shortcuts (hjkl, 0/$, /n, y/p, x, d, u, r, o, a, g) remain identical.

---

## Your Cheat Sheet While You Learn

Hold the Leader key and the HUD appears with five organized sections:

Screenshot — HUD showing KindaVim command groups:
```
  ┌─────────────────────────────────────────────────────┐
  │  Navigation Layer                                    │
  │                                                      │
  │  Movement    Word Motion   Editing   Search   Clip   │
  │  ─────────  ───────────   ───────   ──────   ─────  │
  │  h ← left   w word →      x del     / find   y yank │
  │  j ↓ down   b ← word      d bksp    n next   p put  │
  │  k ↑ up     e end word    u undo                     │
  │  l → right                r redo                     │
  │  0 ln start               o open ln                  │
  │  $ ln end                                            │
  │  gg go top                                           │
  └─────────────────────────────────────────────────────┘
```

The keyboard overlay highlights KindaVim keys in **green** (vs. orange for the standard Vim collection) so you can tell at a glance which collection is active.

---

## Tips

- **Start with KindaVim alone** — get comfortable with Normal/Visual modes before adding KeyPath's leader-key shortcuts on top
- **Leader shortcuts are for Insert mode** — when you're typing and want a quick navigation jump without leaving Insert mode, hold Leader
- **The overlay is your cheat sheet** — keep it visible while learning; the green-highlighted keys show exactly what's available
- **Word motions make the biggest difference** — `w`/`b`/`e` for word-level jumps are much faster than character-by-character with hjkl

---

## Where to Go Next

- **[What You Can Build]({{ '/guides/use-cases/' | relative_url }})** — See all the things KeyPath can do
- **[Shortcuts Without Reaching]({{ '/guides/home-row-mods/' | relative_url }})** — Combine KindaVim with home row modifiers
- **[One Key, Multiple Actions]({{ '/guides/tap-hold/' | relative_url }})** — Learn how Leader key tap-hold works
- **[Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})** — Layers, modifiers, and dual-role keys explained

## External Resources

- **[KindaVim ↗](https://kindavim.app)** — Download and documentation
- **[KindaVim on GitHub ↗](https://github.com/godbout/kindaVim)** — Source code and issue tracker
- **[Vim Cheat Sheet ↗](https://vim.rtorr.com/)** — Quick reference for all Vim commands
