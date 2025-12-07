# Home Row Mods—Deep Dive

> This document contains the full technical explanation of Home Row Mods (HRM) and why KeyPath/Kanata delivers reliable HRM on Mac. For a quick overview, see the [README](../README.md#home-row-mods).

---

## What are Home Row Mods?

**KeyPath is the only Mac tool that enables [Home Row Mods](https://precondition.github.io/home-row-mods) in pure software with reliability comparable to hardware firmware like QMK or ZMK.**

<div align="center">
  <img src="images/mac-hrm.png" alt="Home Row Mods Diagram" width="500"/>
</div>

Home Row Mods (HRM) turn the keys under your fingers—A, S, D, F and J, K, L, ;—into dual-function keys:

- **Tap** → types the letter (`a`, `s`, `d`, `f`)
- **Hold** → activates a modifier (`Ctrl`, `Alt`, `Cmd`, `Shift`)

This means you never have to move your hands from the home row to press modifiers. It's a game-changer for ergonomics, speed, and reducing repetitive strain.

---

## Why Most Mac Tools Fail at HRM

The difference between reliable and unreliable HRM comes down to one thing: **how the software decides tap vs hold**.

### Timeout-Only Detection (Karabiner-Elements)

"If the key is held longer than X milliseconds, it's a hold."

This sounds reasonable but causes constant misfires during fast typing. The software can't distinguish:
- "I'm holding F to modify the next key" 
- "I'm just rolling through F-G-H quickly"

### Press-Aware Detection (Kanata)

"If another key is pressed while this key is down, it's a hold."

This is the insight that makes HRM work. Press `F` (mapped to Shift) then `J`, and you get `Shift+J` instantly—no timeout required.

---

## Why Kanata Succeeds

Kanata implements multiple tap-hold strategies refined over years across QMK, KMonad, and now Kanata:

| Strategy | How it works |
|----------|--------------|
| **tap-hold-press** | Hold activates immediately when any other key is pressed |
| **tap-hold-release** | Hold activates when another key is pressed *and released* |
| **tap-hold-except-keys** | Certain keys bypass hold detection (for fine-tuning) |

This is the same approach that makes HRM reliable on custom keyboards running QMK or ZMK firmware. Kanata brings that firmware-grade logic to software.

---

## Karabiner-Elements vs Hammerspoon

### Karabiner-Elements

Uses timeout-only detection (`to_if_alone`, `to_if_held_down`). It works for casual use, but fast typists experience frequent misfires. There's no way to enable press-aware detection—it's not how the tool is architected.

### Hammerspoon

Has the primitives to implement press-aware detection—it uses the same macOS event tap API as Kanata. But nobody has built and maintained a reliable HRM implementation. 

You'd be writing ~1000 lines of Lua state machine code and debugging edge cases that Kanata has already solved over years of community iteration. Theoretically possible; practically, you'd be reinventing the wheel.

**Why?** The algorithm complexity is significant:
- Track multiple key states simultaneously
- Handle rollover (pressing a new key before releasing the previous)
- Implement per-key exceptions
- Integrate with layer switching
- Handle edge cases discovered over years of community use

---

## Where QMK/ZMK Still Go Further

Hardware firmware such as QMK and ZMK still have headroom KeyPath hasn't reached yet:

- **Bilateral combos** — Modifiers on one hand only activate when the next keypress comes from the opposite hand
- **Hold-per-finger heuristics** — Different timing based on which finger is pressing
- **Highly customized priority rules** — See [this QMK deep dive](https://www.reddit.com/r/ErgoMechKeyboards/comments/1f18d8h/i_have_fixed_home_row_mods_in_qmk_for_everyone/)

Those projects can coordinate across thumb clusters, read matrix-level timing, and run combo detection before the OS ever sees a key. 

KeyPath's HRM is firmware-grade for most workflows, but if you want experimental combo models or split-keyboard-specific logic, QMK/ZMK remains the bleeding edge. Our goal is to keep closing that gap while retaining a macOS-native UX.

---

## Learn More

- [Home Row Mods Guide](https://precondition.github.io/home-row-mods) — The canonical introduction
- [Taming Home Row Mods with Bilateral Combinations](https://sunaku.github.io/home-row-mods.html) — Deep dive into advanced HRM tuning
- [Home Row Mods Explained (Video)](https://www.youtube.com/watch?v=sLWQ4Gx88h4) — Visual introduction
- [Home Row Mods in Practice (Video)](https://www.youtube.com/watch?v=4yiMbP_ZySQ) — Real-world usage demo

---

## Technical Details

### The Core Algorithm

The key insight behind reliable HRM is **press-aware detection**:

```
if (hrm_key_is_down AND another_key_pressed) {
    activate_hold()  // Don't wait for timeout
}
```

This simple check transforms HRM from "frustrating misfires" to "actually usable."

### Kanata's Implementation

Kanata's tap-hold engine mirrors QMK/ZMK with:
- Multiple detection strategies (`tap-hold-press`, `tap-hold-release`)
- Per-key exception lists
- Integration with layer switching (`layer-while-held`)
- Configurable timing parameters

The configuration is expressed in Kanata's Lisp-like syntax:

```lisp
(defalias
  a (tap-hold-press 200 200 a lmet)   ;; A = Cmd when held
  s (tap-hold-press 200 200 s lalt)   ;; S = Alt when held
  d (tap-hold-press 200 200 d lsft)   ;; D = Shift when held
  f (tap-hold-press 200 200 f lctl)   ;; F = Ctrl when held
)
```

KeyPath generates this configuration through its visual interface, so you don't need to write it by hand.
