![Keyboard Concepts](header-concepts.png)

# Keyboard Concepts for Mac Users

If you've never customized a keyboard beyond **System Settings > Keyboard > Modifier Keys**, this page is for you. We'll start with the simplest possible change and build up to more powerful ideas.

---

## Start here: fix one annoying key

Look at your keyboard. Caps Lock sits in prime real estate — right next to the home row, easy to reach with your pinky. But when was the last time you actually *wanted* Caps Lock?

Now look at Escape. It's way up in the corner, a full stretch from the home row. But you press it constantly — dismissing dialogs, canceling searches, exiting full-screen video, leaving editing modes.

The fix: **make Caps Lock send Escape instead.**

```
  Before:                          After:
  ┌──────┐                        ┌──────┐
  │ Caps │  (useless)             │ Esc  │  (useful!)
  │ Lock │                        │      │
  └──────┘                        └──────┘
  ┌──────┐                        ┌──────┐
  │ Esc  │  (far away)            │ Esc  │  (still there)
  └──────┘                        └──────┘
```

This is a **remap** — making one key behave as another. It's the simplest thing you can do, and it takes about ten seconds in KeyPath.

<!-- screenshot: id="concepts-new-rule-dialog" method="snapshot" view="CustomRulesInlineEditor" state="start:caps_lock,finish:escape,hold:disabled" -->
Screenshot — Creating a simple remap in the Custom Rules tab:
```
  ┌─────────────────────────────────────────────────────┐
  │  New Rule                                           │
  │                                                     │
  │  Start key:    [ caps_lock      ▾ ]                 │
  │  Finish key:   [ escape         ▾ ]                 │
  │                                                     │
  │                              [ Cancel ]  [ Save ]   │
  └─────────────────────────────────────────────────────┘
```

That's it. One key remapped. No config files, no JSON, no terminal commands. But this is just the beginning — once you see how easy it is, you'll want to do more.

---

## What if one key could do two things?

That Caps Lock remap is nice, but now you've lost Caps Lock entirely. What if the key could be *both* — Escape when you tap it, and something more useful (like Control) when you hold it?

This is called **tap-hold**: one key, two jobs depending on how you press it.

- **Tap** quickly → Escape
- **Hold** down → Control

```
  ┌──────────┐
  │ Caps Lock│
  │          │
  │ tap: Esc │    Press and release quickly → Escape
  │hold: Ctrl│    Hold down + press another key → Control
  └──────────┘
```

![Tap-hold — one key, two jobs](concepts-tap-hold.png)

Now you get Escape *and* a conveniently placed Control — from one key. No sacrifices.

The tricky part is timing — how does KeyPath know if you meant to tap or hold? It watches for a threshold (default: 200ms) and what other keys you press during the decision window. You can tune this to match your typing speed.

![Tap-hold timing — tap vs hold threshold](concepts-tap-hold-timing.png)

See the [One Key, Multiple Actions guide](help:tap-hold) for all the options.

---

## Now imagine a whole second keyboard

You just saw one key doing two things. What if you could do that with *every* key? That's what **layers** are.

Think of layers like having multiple keyboards stacked on top of each other. You're always typing on one layer, and you can switch between them.

![Layers — base and navigation](concepts-layers.png)

**You already use layers on your Mac** — holding Shift gives you a different "layer" of characters (uppercase letters, symbols like ! @ # $). Keyboard remapping just lets you create as many layers as you want.

For example, a navigation layer puts arrow keys right on the home row — no more reaching for those tiny arrow keys on your MacBook:

```
  Base layer (normal typing):      Navigation layer (hold trigger):
  ┌───┬───┬───┬───┐               ┌───┬───┬───┬───┐
  │ H │ J │ K │ L │               │ ← │ ↓ │ ↑ │ → │
  └───┴───┴───┴───┘               └───┴───┴───┴───┘

  Hold a trigger key to enter the nav layer,
  release to go back to normal typing.
```

Common layers:
- **Navigation** — arrow keys, Page Up/Down, Home/End on the home row
- **Number** — a numpad layout under your right hand
- **Symbol** — brackets, braces, and programming symbols within easy reach
- **Launcher** — every key launches a different app

---

## Put modifiers under your fingertips

You use these modifiers every day on your Mac:

| macOS name | Symbol | What it does |
|---|---|---|
| **Command** | ⌘ | The primary modifier — ⌘C to copy, ⌘V to paste |
| **Option** | ⌥ | Secondary modifier — special characters, alternate actions |
| **Control** | ⌃ | Used in Terminal, Emacs-style shortcuts |
| **Shift** | ⇧ | Uppercase letters, alternate toolbar actions |

The problem: they're all in the corners. Every shortcut forces your fingers off the home row. Over a workday, that's thousands of small reaches.

**Home row mods** fix this using the same tap-hold idea — your home row letter keys double as modifiers when held:

```
  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
  │  A  │ │  S  │ │  D  │ │  F  │     │  J  │ │  K  │ │  L  │ │  ;  │
  │ ⇧   │ │ ⌃   │ │ ⌥   │ │ ⌘   │     │ ⌘   │ │ ⌥   │ │ ⌃   │ │ ⇧   │
  └─────┘ └─────┘ └─────┘ └─────┘     └─────┘ └─────┘ └─────┘ └─────┘
              Tap for letters, hold for modifiers
```

![Home row mods — modifiers on the home row](concepts-home-row-mods.png)

Hold F + press C = ⌘C (Copy). Hold A + press Tab = ⇧Tab. Your hands never move.

The challenge is avoiding misfires during fast typing. KeyPath uses opposite-hand activation (same-hand = letter, cross-hand = modifier), fast typing protection, and per-finger timing to make it reliable. Read the full [Shortcuts Without Reaching guide](help:home-row-mods) for details.

---

## Never run out of shortcuts

Every modifier combination you try is already taken by some app. The solution: create a modifier that *no app uses*.

- **Hyper** = Control + Option + Command + Shift (all four at once)
- **Meh** = Control + Option + Shift (three modifiers, no Command)

No application on your Mac uses these combinations, so they give you dozens of shortcuts that will never conflict with anything. A common setup: tap Caps Lock for Escape, hold it for Hyper — now every letter key becomes a unique, conflict-free shortcut.

![Conflict-free shortcuts — Hyper gives you 36+ unique bindings](concepts-hyper-key.png)

---

## Pack even more into a single key

**Tap-dance** takes the dual-role idea further: different actions based on how many *times* you tap.

```
  Caps Lock:
  1 tap  → Escape
  2 taps → Caps Lock (when you actually need it)
  3 taps → Control
```

![Tap-dance — multiple taps, multiple actions](concepts-tap-dance.png)

This is great for keys you rarely use — pack multiple functions into one key without adding complexity to everyday typing.

Beyond single keys, you can trigger actions from combinations:

- **Chord** — press two keys simultaneously (e.g., J+K together → trigger an action)
- **Sequence** — press keys one after another (e.g., Space then S then M → open Messages)
- **Leader key** — press a "leader" key, then type a short sequence. Like Vim's leader key but for your whole system.

![Chords and sequences](concepts-chords-sequences.png)

These let you create memorable shortcuts without running out of modifier combinations.

---

## The big picture

Here's how all these concepts build on each other:

```
  Simple remap           One key does two things
  (Caps Lock → Esc)  →   (tap: Esc, hold: Ctrl)
         │                       │
         ↓                       ↓
  A whole second          Modifiers on the
  keyboard (layers)  →   home row (HRM)
         │                       │
         ↓                       ↓
  Conflict-free           Multiple taps,
  shortcuts (Hyper)      chords, sequences
```

Start with a simple remap. Get comfortable. Then add the next idea when you're ready. There's no rush.

---

## Where to go next

- **[What You Can Build](help:use-cases)** — Concrete examples of what's possible with KeyPath
- **[Shortcuts Without Reaching](help:home-row-mods)** — The most popular advanced technique
- **[One Key, Multiple Actions](help:tap-hold)** — All the details on dual-role keys
- **[Launching Apps](help:action-uri)** — Launch apps, URLs, and folders from your keyboard
- **[Alternative Layouts](help:alternative-layouts)** — Colemak, Dvorak, Workman, and other keymaps
- **[Keyboard Layouts](help:keyboard-layouts)** — Physical keyboard support (ANSI, split, ergonomic)
- **[Back to Docs](https://keypath-app.com)** — See all available guides

## External resources

These community resources go deeper into keyboard customization concepts:

- **[The Home Row Mods Guide (Precondition)](https://precondition.github.io/home-row-mods)** — The definitive community reference on home row mods ↗
- **[Kanata documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)** — Full configuration reference for the engine behind KeyPath ↗
- **[QMK Firmware](https://docs.qmk.fm/)** — If you're interested in firmware-level remapping on custom keyboards ↗
- **[r/ErgoMechKeyboards](https://www.reddit.com/r/ErgoMechKeyboards/)** — Active community discussing keyboard layouts, layers, and ergonomics ↗
- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** — Another macOS remapping tool, if you want to compare approaches ↗
- **[Ben Vallack's keyboard videos](https://www.youtube.com/watch?v=3zgJLUHQYjY&list=PLCZYyvXAdQpsVKWXVE-7u2w07XXp9NoWI)** — Advanced keyboard layout exploration and experimentation ↗
