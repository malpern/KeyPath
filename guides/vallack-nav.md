---
layout: default
title: "Ben Vallack Navigation"
description: "A complete home row navigation system inspired by keyboard minimalist Ben Vallack"
theme: parchment
permalink: /guides/vallack-nav/
---

# Ben Vallack Navigation

This pack is a complete home row navigation system inspired by [Ben Vallack](https://www.youtube.com/@BenVallacksKeyboards), a keyboard designer and YouTuber known for pushing the limits of what a keyboard can do. His channel explores minimal keyboard layouts, custom firmware, and the idea that your fingers should never leave the home row — for anything.

Ben's approach is opinionated: modifiers move to the top row, the index fingers become layer toggles, and the entire right hand becomes a navigation surface. It's a different philosophy from the default Vim Navigation pack — where that pack adds navigation alongside your normal keyboard, this one *redesigns* your keyboard around navigation.

If you're new to keyboard customization, start with [Home Row Arrows]({{ '/guides/remapping/' | relative_url }}) or [Vim Navigation]({{ '/guides/vim-navigation/' | relative_url }}) first. Come back here when you're ready to go deeper.

---

## What you get

Hold either index finger key (F or J) and your keyboard transforms:

- **H, J, K, L** become arrow keys — left, down, up, right
- **Y** copies, **;** pastes — clipboard without leaving the home row
- **U** deletes backward, **I** presses Enter
- **E** and **R** switch browser tabs — previous and next
- **S** and **D** jump to the start and end of a line
- **A** opens the app switcher (⌘Tab)

Release your index finger and everything goes back to normal. Both F and J activate the same layer, so you can use whichever hand is more comfortable.

---

## The navigation layer in detail

When you hold F or J, here's what every key does:

### Right hand — navigation

```
  ┌───┬───┬───┬───┬───┐
  │ Y │ U │ I │ O │ P │
  │⌘C │ ⌫ │ ↵ │   │   │
  ├───┼───┼───┼───┼───┤
  │ H │ J │ K │ L │ ; │
  │ ← │ ↓ │ ↑ │ → │⌘V │
  └───┴───┴───┴───┴───┘
```

The core navigation cluster follows the Vim HJKL layout: H is left, J is down, K is up, L is right. But unlike standalone Vim Navigation, the surrounding keys are mapped to editing actions — backspace on U, enter on I, copy on Y, paste on semicolon. Your right hand handles both movement and editing without reaching.

### Left hand — switching and jumping

```
  ┌───┬───┬───┬───┬───┐
  │ Q │ W │ E │ R │ T │
  │Tab│Esc│◀tab│tab▶│⌘[ │
  ├───┼───┼───┼───┼───┤
  │ A │ S │ D │ G │ V │
  │⌘Tab│Home│End│ 📸 │⌘] │
  └───┴───┴───┴───┴───┘
```

Your left hand handles context switching. E and R cycle browser tabs (Ctrl+Shift+Tab and Ctrl+Tab). A opens the app switcher. S and D jump to the start and end of the current line. T and V navigate back and forward in apps that support ⌘[ and ⌘]. G takes a screenshot.

---

## Modifiers on the top row

Here's where the Vallack approach gets distinctive. Standard [home row mods]({{ '/guides/home-row-mods/' | relative_url }}) put modifiers on A, S, D, F — but that creates a conflict, because the Vallack nav layer also uses those keys for actions (A is app switcher, S is Home, D is End).

Ben's solution: move modifiers to the top row.

```
  Standard home row mods:           Vallack modifiers:
  ┌───┬───┬───┬───┐                ┌───┬───┬───┐  ┌───┬───┬───┐
  │   │   │   │   │                │ Q │ W │ E │  │ U │ I │ O │
  │   │   │   │   │                │Ctl│Opt│Cmd│  │Cmd│Opt│Ctl│
  ├───┼───┼───┼───┤                └───┴───┴───┘  └───┴───┴───┘
  │ A │ S │ D │ F │
  │Ctl│Opt│Sft│Cmd│
  └───┴───┴───┴───┘
```

Tap Q normally to type "q". Hold Q to get Control. Same for W (Option) and E (Command) on the left, and U (Command), I (Option), O (Control) on the right.

This frees the entire home row for navigation and typing. No conflicts — modifiers live on a row you don't type on as frequently, and the top row is easy to reach without moving your hands.

---

## Three collections working together

When you install the Ben Vallack Nav pack, KeyPath sets up three coordinated collections:

| Collection | What it does |
|-----------|-------------|
| **Vallack Navigation** | The layer mappings — arrows, clipboard, tab switching, line navigation |
| **Ben's Modifiers** | Top-row modifiers (Q/W/E and U/I/O) instead of standard home row mods |
| **Vallack Layer Toggles** | F and J as hold-to-activate triggers for the navigation layer |

These three are designed to work as a system. Installing the pack enables all three and configures them to the Vallack defaults. You can adjust individual settings in each collection if you want to customize.

---

## Who is this for?

**Good fit if you:**
- Want everything accessible without moving your hands — arrows, editing, clipboard, tabs
- Are comfortable with an opinionated layout that changes how your whole keyboard works
- Type frequently and want to minimize hand travel
- Enjoy the mechanical keyboard customization community and want to try a layout that a well-known designer uses daily

**Try something simpler first if you:**
- Just want arrow keys on the home row → [Home Row Arrows]({{ '/guides/remapping/' | relative_url }})
- Want Vim-style navigation but keep your standard modifiers → [Vim Navigation]({{ '/guides/vim-navigation/' | relative_url }})
- Are new to keyboard customization → start with [Remapping]({{ '/guides/remapping/' | relative_url }})

---

## Installing

1. Open the **Pack Gallery**
2. Find **Ben Vallack Nav** and click **Install**
3. KeyPath will ask about conflicts if you have Home Row Mods or Vim Navigation enabled — the Vallack system replaces both

<!-- Screenshot: Pack Gallery showing Ben Vallack Nav -->
![Screenshot — Ben Vallack Nav in the Pack Gallery]({{ '/images/help/placeholder-pack-vallack-install.png' | relative_url }})

Or from the command line:

```bash
keypath pack install vallack-system
```

---

## Tips for getting started

**Start with navigation.** Hold F, press HJKL to move around in a text editor. Don't worry about the other keys yet — just get comfortable with arrows.

**Add clipboard next.** Once HJKL feels natural, start using Y (copy) and ; (paste). Select text with Shift+arrows (hold Shift on the left hand while pressing HJKL), then Y to copy.

**Tab switching last.** E (previous tab) and R (next tab) are the most powerful once you're in the flow — navigate code, switch tabs, paste a snippet, all without touching the mouse.

**Give the top-row modifiers a week.** Moving modifiers off the home row feels strange at first. The payoff is that your home row is purely for typing and navigation, with no timing-sensitive tap-hold decisions on your most-used keys.

---

## Learn more from Ben

Ben Vallack's YouTube channel is the best place to understand the thinking behind this layout:

- **[Ben Vallack's keyboard playlist](https://www.youtube.com/watch?v=3zgJLUHQYjY&list=PLCZYyvXAdQpsVKWXVE-7u2w07XXp9NoWI)** — His journey from standard keyboards to minimal layouts ↗
- **[Ben Vallack's channel](https://www.youtube.com/@BenVallacksKeyboards)** — Keyboard reviews, layout experiments, and workflow demos ↗

---

## Related guides

- **[Home Row Arrows]({{ '/guides/remapping/' | relative_url }})** — Simpler: just hold F for IJKL arrows
- **[Vim Navigation]({{ '/guides/vim-navigation/' | relative_url }})** — Hold Space for navigation + editing
- **[Home Row Mods]({{ '/guides/home-row-mods/' | relative_url }})** — Standard modifier placement (conflicts with Vallack)
- **[Packs & Layers]({{ '/guides/packs/' | relative_url }})** — Browse all available packs
