# Home Row Mods

```
  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
  │  A  │ │  S  │ │  D  │ │  F  │     │  J  │ │  K  │ │  L  │ │  ;  │
  │ ⇧   │ │ ⌃   │ │ ⌥   │ │ ⌘   │     │ ⌘   │ │ ⌥   │ │ ⌃   │ │ ⇧   │
  └─────┘ └─────┘ └─────┘ └─────┘     └─────┘ └─────┘ └─────┘ └─────┘
              Tap for letters, hold for modifiers
```

---

## What Are Home Row Mods?

- Your home row keys (A S D F / J K L ;) double as modifier keys.
- Tap quickly for the letter, hold briefly for the modifier.
- Eliminates reaching for Shift, Ctrl, Alt, and Cmd — your fingers stay on the home row.

```
  Tap:     [F] ──→  f
  Hold:    [F] ━━→  ⌘ Cmd
```

---

## Getting Started

- Default layout: **CAGS** (Cmd on index, Alt on middle, Ctrl on ring, Shift on pinky).
- Start with the defaults and practice for a few days.
- Occasional misfires during fast typing are normal at first — they improve with tuning.
- If a specific finger misfires, try the per-finger timing adjustments below.

```
  Pinky  →  Shift        Ring  →  Ctrl
  Middle →  Alt          Index →  Cmd
```

---

## Tuning Your Setup

### Typing Feel slider

Slide toward "More Letters" for a longer tap window (fewer accidental modifiers) or toward "More Modifiers" for quicker modifier activation.

### Per-finger sensitivity

Pinkies are slower than index fingers. Add extra tolerance for slower fingers to prevent accidental holds.

### Quick tap

When enabled, favors the letter when you tap and release quickly, even if another key was pressed during the window.

*Start with defaults, then adjust one parameter at a time.*

```
  ├──── Tap (letter) ────┼──── Hold (modifier) ────┤
  0 ms                 200 ms                    ∞
```

---

## How KeyPath Makes Home Row Mods Reliable

### Split-hand detection

KeyPath tracks which keyboard half each key belongs to. Same-hand key presses during the tap-hold window immediately produce the letter (fast typing), while opposite-hand presses allow the modifier to activate (intentional chording). Based on Kanata's `tap-hold-release-keys` and the approach recommended by Kanata's creator.

```
  Left Hand                     Right Hand
  ┌───┬───┬───┬───┬───┐       ┌───┬───┬───┬───┬───┐
  │ Q │ W │ E │ R │ T │       │ Y │ U │ I │ O │ P │
  ├───┼───┼───┼───┼───┤       ├───┼───┼───┼───┼───┤
  │ A │ S │ D │ F │ G │       │ H │ J │ K │ L │ ; │
  ├───┼───┼───┼───┼───┤       ├───┼───┼───┼───┼───┤
  │ Z │ X │ C │ V │ B │       │ N │ M │ , │ . │ / │
  └───┴───┴───┴───┴───┘       └───┴───┴───┴───┴───┘

  Same hand   → tap (letter)
  Cross hand  → hold (modifier)
```

---

### Per-finger timing

Different fingers move at different speeds. KeyPath lets you add extra tolerance for slower fingers (pinkies) while keeping faster fingers (index) responsive.

```
  Pinky   ████████████████████░  (most tolerance)
  Ring    █████████████░░░░░░░░
  Middle  █████████░░░░░░░░░░░░
  Index   ██████░░░░░░░░░░░░░░░  (least tolerance)
```

---

## KeyPath vs. Karabiner-Elements

| Aspect | KeyPath | Karabiner |
|---|---|---|
| Tap-hold variants | 4 variants (tunable per key) | Single `to_if_alone` |
| Split-hand | Built-in | Complex JSON workaround |
| Per-finger timing | Per-key offsets | Global timeout only |
| Layer integration | Hold-activate layers | Separate rule sets |
| Configuration | Visual UI with sliders | JSON editing |
| Engine | Kanata (purpose-built) | General-purpose JSON |

Karabiner-Elements can technically achieve home row mods, but it requires hand-crafting complex JSON rules and offers fewer anti-misfire tools. KeyPath's Kanata backend was designed with tap-hold as a first-class concept, giving you more precise control with less configuration effort.

```
  KeyPath:   [ Visual sliders ]
  Karabiner: {"type":"basic","from":{...}}
```

---

## The Cutting Edge

Techniques being developed in the mechanical keyboard community that represent where HRM is headed:

### Anti-cascade / nomods layer

After a tap resolves, temporarily disable all home row mods for the rest of the typing burst, re-enabling them after a brief idle. Prevents chain-reaction misfires. Planned for a future KeyPath update.

### Typing streak detection

Track sustained typing bursts and suppress modifier activation during the streak. Only re-enable after a pause. Pioneered by Sunaku's bilateral combinations in QMK.

### Achordion / Chordal Hold

QMK libraries (by Pascal Getreuer) that make the tap/hold decision based on which hand pressed the next key, operating directly in firmware. Chordal Hold was merged into QMK core in Feb 2025.

### Eager mods

Apply the modifier immediately while the decision is still pending. If the key resolves as a tap, the modifier is retroactively canceled. Reduces perceived latency for intentional modifier use.

### Shift exemption

Shift is the most common modifier during typing. Advanced configs exempt Shift from streak suppression so capitalization works naturally.

---

## Resources

- [Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold)
- [The Home Row Mods Guide (precondition.github.io)](https://precondition.github.io/home-row-mods)
- [jtroo's advanced Kanata config](https://github.com/jtroo/kanata/blob/main/cfg_samples/jtroo.kbd)
