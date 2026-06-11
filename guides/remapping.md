---
layout: default
title: "Remapping Keys"
description: "Change what any key does — from fixing one annoying key to redesigning your whole keyboard"
theme: parchment
header_image: header-remapping.png
permalink: /guides/remapping/
---

# Remapping Keys

Remapping means making a key do something different than what's printed on it. A key you never use becomes one you press constantly. An awkward reach becomes a comfortable press.

This is the most useful thing KeyPath does. If you've never remapped a key before, this guide will get you there in under a minute — and by the end, you'll see why people redesign their whole keyboard.

---

## The problem

You navigate text every day — moving the cursor through documents, emails, code, spreadsheets. Every time you reach for the arrow keys, your right hand leaves the home row:

```
                                          your hand has to
                                          travel here ──┐
                                                        ↓
  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐      ┌───┐
  │   │   │   │   │   │   │   │   │   │   │      │ ↑ │
  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤  ┌───┼───┼───┐
  │   │   │   │ F │   │   │ J │   │   │   │  │ ← │ ↓ │ → │
  └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘  └───┴───┴───┘
                  ↑                   ↑
            your left hand      your right hand
            stays here          has to leave
```

On a MacBook, those arrow keys are tiny. You look down to find them. You lose your place in the text. Then you move your hand back to the home row and find your position again. Dozens of times a day.

---

## Your first remap: Home Row Arrows

What if your right hand could stay on the home row and *still* have arrow keys?

**Home Row Arrows** turns F into a trigger. Tap F normally and it types "f". But hold F, and your right hand becomes arrow keys:

```
  Hold F, then press:

  ┌───┬───┬───┬───┐
  │   │ ↑ │   │   │     I = Up
  ├───┼───┼───┼───┤
  │ ← │ ↓ │ → │   │     J = Left, K = Down, L = Right
  └───┴───┴───┴───┘

  Plus: H = Home, ; = End, U = Page Up, O = Page Down
```

The arrow layout matches the physical arrow keys you already know — up is above down, left and right are on either side. No new layout to memorize.

### Try it now

KeyPath installs Home Row Arrows by default. If it's already running, try it:

1. Open any text editor or document
2. **Hold F** (don't release)
3. Press **J, K, I, or L** to move the cursor
4. **Release F** to go back to normal typing

<!-- Screenshot: Overlay showing Home Row Arrows layer active, IJKL highlighted as arrows -->
![Screenshot — Home Row Arrows active in the overlay]({{ '/images/help/placeholder-overlay-home-row-arrows.png' | relative_url }})

That's it. Your hand never left the home row. No reaching, no looking down, no tiny arrow keys.

### Prefer Vim-style HJKL?

If you're a developer who already knows Vim's HJKL navigation, you can switch layouts in the pack settings:

1. Open the **Pack Gallery**
2. Click **Home Row Arrows**
3. Choose **Vim-Style** from the layout picker

```
  Inverted-T (default):            Vim-Style:
  ┌───┬───┬───┬───┐               ┌───┬───┬───┬───┐
  │   │ ↑ │   │   │               │ ← │ ↓ │ ↑ │ → │
  ├───┼───┼───┼───┤               ├───┼───┼───┼───┤
  │ ← │ ↓ │ → │   │               │ H │ J │ K │ L │
  └───┴───┴───┴───┘               └───┴───┴───┴───┘
```

<!-- Screenshot: Pack detail showing layout picker with Inverted-T and Vim options -->
![Screenshot — Home Row Arrows layout picker]({{ '/images/help/placeholder-pack-detail-arrows-picker.png' | relative_url }})

### If it's not installed yet

1. Open KeyPath from the menu bar
2. Open the **Pack Gallery**
3. Find **Home Row Arrows** and click **Install**

<!-- Screenshot: Pack Gallery showing Home Row Arrows pack -->
![Screenshot — Home Row Arrows in the Pack Gallery]({{ '/images/help/placeholder-pack-gallery-home-row-arrows.png' | relative_url }})

Or from the command line:

```bash
keypath pack install home-row-arrows
```

---

## What just happened?

When you held F and pressed J, KeyPath told the [Kanata](https://github.com/jtroo/kanata) remapping engine to intercept the keypress and send Left Arrow instead. This happens at a level below your apps — every application on your Mac sees an arrow key, not the letter J.

```
  You press:        KeyPath intercepts:      Your Mac sees:
  ┌───┐ + ┌───┐     ┌───────────────┐       ┌───┐
  │ F │   │ J │  →   │    Kanata     │   →   │ ← │
  │   │   │   │      │    engine     │       │   │
  └───┘   └───┘      └───────────────┘       └───┘
  (hold)  (press)
```

When you release F, everything goes back to normal. F types "f" when tapped. J types "j" when tapped. The magic only happens when F is held.

Kanata is the open-source keyboard remapping engine that powers KeyPath. It runs as a system service, so your remaps work in every app, every context — even before you log in. KeyPath provides the visual interface; Kanata provides the engine.

---

## A simpler remap: one key becomes another

Home Row Arrows uses a powerful technique (tap-hold + a layer), but remapping can also be much simpler. You can make one key behave as another key — no holding required.

### Caps Lock → Escape

The most popular simple remap. Caps Lock sits in prime real estate next to the home row, but it's useless for most people. Escape is far away but you press it constantly — dismissing dialogs, canceling searches, exiting full-screen.

1. Open the **Pack Gallery**
2. Install **Caps Lock Remap**

Done. Caps Lock now sends Escape every time you press it.

### Right Option → Forward Delete

Macs don't have a Forward Delete key (delete the character *after* the cursor). Right Option is right there and almost nobody uses it deliberately. Remap it:

```bash
keypath remap right_option delete
```

### More popular simple remaps

| Remap | Why |
|-------|-----|
| Caps Lock → Escape | Move Escape to the home row |
| Right Option → Forward Delete | Add the missing Forward Delete key |
| Right Control → Enter | Bring Enter closer to the home row |
| Right Command → Hyper | A modifier no app uses — free shortcut real estate |

---

## Seeing your remaps

The keyboard overlay shows you what every key does right now. Remapped keys are highlighted so you can always tell what's been changed.

<!-- Screenshot: Overlay showing remapped keys highlighted -->
![Screenshot — The overlay highlighting remapped keys]({{ '/images/help/placeholder-overlay-remapped-keys.png' | relative_url }})

Click any key to see its current mapping. If you ever forget what you've changed, the overlay is your map.

---

## Undoing a remap

Changed your mind? Nothing is permanent:

- **Pack Gallery** — click **Uninstall** on the pack
- **Overlay** — click the key, set it back to its original output
- **CLI** — `keypath unmap caps_lock`

Experiment freely.

---

## What's next?

You've seen two kinds of remapping — a simple key swap (Caps Lock → Escape) and a hold-activated layer (Home Row Arrows). That second one is the gateway to much more.

**[Tap-Hold]({{ '/guides/tap-hold/' | relative_url }})** — The technique Home Row Arrows uses. One key, two jobs: tap for one thing, hold for another. This is the second fundamental concept, and it unlocks everything else.

**[Layers]({{ '/guides/concepts/' | relative_url }})** — Home Row Arrows gave you one extra layer (arrows). Imagine having *several* — a numpad layer, a symbol layer, an app launcher layer. That's where the real power lives.

**[Browse the Pack Gallery]({{ '/guides/packs/' | relative_url }})** — Pre-built feature packs you install with one click. Start with what's already on and explore from there.

---

## Quick reference

### Pack Gallery remaps

| Pack | What it does |
|------|-------------|
| [Home Row Arrows]({{ '/guides/packs/' | relative_url }}) | Hold F for arrow keys on IJKL. Installed by default. |
| [Caps Lock Remap]({{ '/guides/packs/' | relative_url }}) | Tap: Escape (or Backspace/Hyper). Hold: modifier. |
| [Escape Remap]({{ '/guides/packs/' | relative_url }}) | Move Escape to Caps Lock, Backtick, or Tab. |
| [Delete Enhancement]({{ '/guides/packs/' | relative_url }}) | Forward-delete, word-delete, and line-delete from Backspace. |
| [Backup Caps Lock]({{ '/guides/packs/' | relative_url }}) | Both Shift keys together → Caps Lock. |

### CLI remapping

```bash
keypath remap <from> <to>          # Remap a key
keypath unmap <from>               # Remove a remap
keypath pack install <name>        # Install a feature pack
keypath pack uninstall <name>      # Remove a feature pack
keypath rule list                  # See all active rules
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
