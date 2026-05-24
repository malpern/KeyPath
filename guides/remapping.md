---
layout: default
title: "Remapping Keys"
description: "Change what any key does — from fixing one annoying key to redesigning your whole keyboard"
theme: parchment
permalink: /guides/remapping/
---

# Remapping Keys

Remapping means making a key do something different than what's printed on it. Caps Lock becomes Escape. Right Option becomes Delete. A key you never use becomes one you use constantly.

This is the simplest and most useful thing KeyPath does. If you've never remapped a key before, this guide will get you there in under a minute.

---

## Why bother?

Look at your keyboard. Some keys are in perfect spots but do things you rarely need. Others are far away but you reach for them constantly.

```
  Keys you rarely press:            Keys you press all the time:
  ┌──────┐ ┌──────┐ ┌──────┐       ┌──────┐ ┌──────┐ ┌──────┐
  │ Caps │ │Right │ │Right │       │ Esc  │ │ Del  │ │ Ctrl │
  │ Lock │ │Option│ │ Ctrl │       │      │ │      │ │      │
  └──────┘ └──────┘ └──────┘       └──────┘ └──────┘ └──────┘
  (prime real estate,               (awkward reaches,
   gathering dust)                   dozens of times a day)
```

Remapping fixes this mismatch. You move frequently-used actions to comfortable keys. Your fingers travel less. Your wrists stay happier.

---

## Your first remap: Caps Lock to Escape

The most popular remap in the world. Caps Lock sits right next to the home row — easy to reach without looking. Escape is way up in the corner. If you dismiss dialogs, cancel searches, or exit full-screen videos, you press Escape constantly.

### Method 1: Install the Pack (recommended)

The fastest way — one click and you're done.

1. Open KeyPath from the menu bar
2. Open the **Pack Gallery**
3. Find **Caps Lock Remap** and click **Install**

<!-- Screenshot: Pack Gallery showing Caps Lock Remap with Install button -->
![Screenshot — Caps Lock Remap in the Pack Gallery]({{ '/images/help/placeholder-pack-gallery-caps-lock.png' | relative_url }})

That's it. Caps Lock now sends Escape. Try it — press Caps Lock and watch what happens.

The Pack also supports tap-hold — tap for Escape, hold for a modifier like Hyper or Control. You can change this in the pack settings after installing. But for now, the simple remap is all you need.

### Method 2: Use the Keyboard Overlay

If you prefer a more visual approach:

1. Open the **KeyPath overlay** (click the menu bar icon, or use the global hotkey)
2. Click on the **Caps Lock** key in the keyboard visualization
3. In the inspector panel, set the output to **Escape**
4. Click **Apply**

<!-- Screenshot: Overlay with Caps Lock selected, inspector showing output picker -->
![Screenshot — Clicking Caps Lock in the overlay to remap it]({{ '/images/help/placeholder-overlay-remap-caps-lock.png' | relative_url }})

The overlay shows you every key and what it currently does. Clicking any key opens an inspector where you can change its behavior.

### Method 3: Use the Command Line

If you're a Terminal person:

```bash
keypath remap caps_lock esc
```

One command, done. Use `keypath unmap caps_lock` to undo it.

---

## What just happened?

When you remapped Caps Lock to Escape, KeyPath told the Kanata remapping engine to intercept every Caps Lock press and send Escape instead. This happens at a level below your apps — every application on your Mac sees Escape, not Caps Lock. It works in every app, every context, even the login screen.

```
  You press:     KeyPath intercepts:     Your Mac sees:
  ┌──────┐       ┌─────────────┐         ┌──────┐
  │ Caps │  →    │   Kanata    │    →    │ Esc  │
  │ Lock │       │   engine    │         │      │
  └──────┘       └─────────────┘         └──────┘
```

Kanata is the open-source remapping engine that powers KeyPath. It runs as a system service, so your remaps work the moment your Mac boots — no need to open KeyPath first. KeyPath provides the visual interface; [Kanata](https://github.com/jtroo/kanata) provides the engine.

---

## More remaps to try

Once you've got one remap working, here are the most popular next steps:

### Right modifier keys

Most people never press the right-side modifiers. They're prime candidates:

| Remap | Why |
|-------|-----|
| Right Option → Forward Delete | Macs don't have a dedicated Delete key. Now you do. |
| Right Control → Enter | Bring Enter closer to the home row. |
| Right Command → Hyper | A modifier no app uses — perfect for custom shortcuts. |

### Function row

If you use the Touch Bar or never press F-keys directly:

| Remap | Why |
|-------|-----|
| Caps Lock → Escape | The classic — move Escape to the home row. |
| Escape → Caps Lock | If you still need Caps Lock occasionally, swap them. |
| Backtick → Escape | For keyboards where Caps Lock is already taken. |

### Swap two keys

You can swap keys so both still exist, just in different positions:

```
  Before:                          After:
  ┌──────┐ ┌──────┐               ┌──────┐ ┌──────┐
  │ Caps │ │ Esc  │               │ Esc  │ │ Caps │
  └──────┘ └──────┘               └──────┘ └──────┘
```

Install both the **Caps Lock Remap** and **Backup Caps Lock** packs, or use the CLI:

```bash
keypath remap caps_lock esc
keypath remap esc caps_lock
```

---

## Seeing your remaps

The keyboard overlay shows you what every key does right now. Remapped keys are highlighted so you can always tell what's been changed.

<!-- Screenshot: Overlay showing remapped keys highlighted -->
![Screenshot — The overlay highlighting remapped keys]({{ '/images/help/placeholder-overlay-remapped-keys.png' | relative_url }})

Hover over any key to see its current mapping. If you ever forget what you've changed, the overlay is your map.

---

## Undoing a remap

Changed your mind? Three ways to undo:

- **Pack Gallery** — click **Uninstall** on the pack
- **Overlay** — click the key, set it back to its original output
- **CLI** — `keypath unmap caps_lock`

Nothing is permanent. Experiment freely.

---

## What's next?

You've remapped one key. That's the foundation. Here's where it gets interesting:

**[Tap-Hold]({{ '/guides/tap-hold/' | relative_url }})** — What if Caps Lock could be *both* Escape (when tapped) and Control (when held)? One key, two jobs. This is the second fundamental concept, and it changes everything.

**[Browse the Pack Gallery]({{ '/guides/packs/' | relative_url }})** — Pre-built remapping packs you can install with one click. Caps Lock Remap, Escape Remap, Delete Enhancement, and more.

**[Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})** — The full picture of what's possible — layers, home row mods, chords, and how they all build on the simple remap you just did.

---

## Quick reference

### Pack Gallery remaps

| Pack | What it does |
|------|-------------|
| [Caps Lock Remap]({{ '/guides/packs/' | relative_url }}) | Tap: Escape (or Backspace/Hyper). Hold: Hyper (or Control/Shift/Meh). |
| [Escape Remap]({{ '/guides/packs/' | relative_url }}) | Move Escape to Caps Lock, Backtick, or Tab. |
| [Delete Enhancement]({{ '/guides/packs/' | relative_url }}) | Forward-delete, word-delete, and line-delete from Backspace. |
| [Backup Caps Lock]({{ '/guides/packs/' | relative_url }}) | Both Shift keys together → Caps Lock. |

### CLI remapping

```bash
keypath remap <from> <to>          # Remap a key
keypath unmap <from>               # Remove a remap
keypath rule list                  # See all active rules
keypath rule add <from> <to>       # More control over rule creation
```

### Common key names

| Key | Name in KeyPath |
|-----|----------------|
| Caps Lock | `caps_lock` |
| Escape | `esc` |
| Delete/Backspace | `backspace` |
| Forward Delete | `delete` |
| Right Option | `right_option` |
| Right Control | `right_control` |
| Right Command | `right_command` |
| Backtick | `grave_accent` |
