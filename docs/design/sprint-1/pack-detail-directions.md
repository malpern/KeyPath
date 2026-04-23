# Pack Detail — Three Visual Directions

**Sprint:** 1 · Day 5
**Status:** For exec decision — pick one direction to carry forward
**Updated:** Added wireframes for each direction across multiple states
**Decision needed:** Which hypothesis about "what this page is" should shape the rest of the sprint?

---

## Why three directions?

Pack Detail is the fulcrum of the whole product. Every user who installs a pack sees it. Every user who evaluates a pack and bounces saw this page not do its job. It's worth exploring distinct hypotheses before committing to one.

Each direction below is a different **answer to the question "what IS this page?"** — not a different coat of paint. They imply different information hierarchies, different interaction models, and different relationships to the rest of the app.

---

## How to read these wireframes

- `═ ║ ╔ ╗ ╚ ╝` — panels (Pack Detail surface)
- `─ │ ┌ ┐ └ ┘` — containers, sections, sub-elements
- `[ BUTTON ]` — buttons (uppercase indicates primary action)
- `▓▓▓▓░░░░` — sliders (filled = value)
- `● ○` — radio buttons (filled = selected)
- `──────` — horizontal rule / visual separator
- `▒▒▒` — dimmed/backgrounded content
- `· · ·` — glow/highlight/pending state
- `✓` — success indicator
- `✕` — close affordance
- Annotations in `italics and brackets` — [*spatial or state notes*]

The wireframes are intentionally grayscale-minded (ASCII has no color). Real comps will apply the accent color and Liquid Glass materials per §6 of the earlier spec draft.

---

## Direction A — "The Product Page"

**Hypothesis:** *"A pack is a product. This page is a confident, editorial page that sells it."*

**Model:** App Store app page. Spotify album page. Arc's browser profile detail. The pack is a named thing with authorship, a voice, a value proposition. The user's job is to decide whether to adopt it.

### Wireframe A-1: Pre-install state (primary view)

```
╔════════════════════════════════════════════════════════════════╗
║                                                            ✕   ║
║                                                                ║
║                                                                ║
║       HOME-ROW MODS                                            ║
║       ═════════════                                            ║
║                                                                ║
║       by KeyPath Team  ·  v2.1.0  ·  1,240 installs           ║
║                                                                ║
║       Turn your home row into modifier keys. Tap a letter     ║
║       to type it; hold a letter to reach ⌃, ⌥, ⇧, or ⌘        ║
║       without leaving your fingers' resting position.          ║
║                                                                ║
║       ┌────────────────────────────────────────────────────┐  ║
║       │                                                    │  ║
║       │  ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮          │  ║
║       │  │Q│ │W│ │E│ │R│ │T│ │Y│ │U│ │I│ │O│ │P│          │  ║
║       │  ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯          │  ║
║       │   ╭▓╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭─╮ ╭─╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭▓╮         │  ║
║       │   │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│         │  ║
║       │   ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯         │  ║
║       │    ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮                    │  ║
║       │    │Z│ │X│ │C│ │V│ │B│ │N│ │M│                    │  ║
║       │    ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯                    │  ║
║       │                                                    │  ║
║       │  [hero diagram: home-row keys tinted with accent] │  ║
║       └────────────────────────────────────────────────────┘  ║
║                                                                ║
║       What it does                                             ║
║       ────────────                                             ║
║       ·  A   →  Tap: a      Hold: ⌃                            ║
║       ·  S   →  Tap: s      Hold: ⌥                            ║
║       ·  D   →  Tap: d      Hold: ⇧                            ║
║       ·  F   →  Tap: f      Hold: ⌘                            ║
║       ·  J   →  Tap: j      Hold: ⌘                            ║
║       ·  K   →  Tap: k      Hold: ⇧                            ║
║       ·  L   →  Tap: l      Hold: ⌥                            ║
║       ·  ;   →  Tap: ;      Hold: ⌃                            ║
║                                                                ║
║       Quick settings                                           ║
║       ──────────────                                           ║
║       Hold timeout      ▓▓▓▓▓▓▓▓░░░░  180 ms                  ║
║       Layout            ● CAGS     ○ CGAS     ○ Custom         ║
║       Works on keyboard [  Built-in keyboard            ▾ ]    ║
║                                                                ║
║                                                                ║
║                              [ Customize… ]   [ Install ]      ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

[sheet: 640 × ~780 pt, overlays dimmed main window or Gallery]
```

### Wireframe A-2: Post-install, unmodified

```
╔════════════════════════════════════════════════════════════════╗
║                                                            ✕   ║
║                                                                ║
║       HOME-ROW MODS                         ✓ Installed        ║
║       ═════════════                                            ║
║                                                                ║
║       by KeyPath Team  ·  v2.1.0                              ║
║                                                                ║
║       Turn your home row into modifier keys. Tap a letter     ║
║       to type it; hold a letter to reach ⌃, ⌥, ⇧, or ⌘…       ║
║                                                                ║
║       ┌────────────────────────────────────────────────────┐  ║
║       │  [hero diagram — affected keys steady-state tint]  │  ║
║       └────────────────────────────────────────────────────┘  ║
║                                                                ║
║       Currently active on 8 keys                               ║
║                                                                ║
║       Quick settings                                           ║
║       ──────────────                                           ║
║       Hold timeout      ▓▓▓▓▓▓▓▓░░░░  180 ms                  ║
║       Layout            ● CAGS     ○ CGAS     ○ Custom         ║
║                                                                ║
║                                                                ║
║       [ Uninstall ]              [ Edit configuration ]        ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

### Wireframe A-3: Post-install, modified + update available

```
╔════════════════════════════════════════════════════════════════╗
║                                                            ✕   ║
║                                                                ║
║       HOME-ROW MODS                                            ║
║       ═════════════                    ⓘ v2.1.1 available      ║
║                                                                ║
║       by KeyPath Team  ·  v2.1.0                               ║
║                                                                ║
║       ⚠ 1 key modified by you.                                 ║
║         [ Restore defaults ]                                   ║
║                                                                ║
║       ┌────────────────────────────────────────────────────┐  ║
║       │  [diagram: 7 keys steady tint, 1 key outlined only]│  ║
║       └────────────────────────────────────────────────────┘  ║
║                                                                ║
║       Currently active on 7 of 8 keys                          ║
║                                                                ║
║       Quick settings                                           ║
║       ──────────────                                           ║
║       Hold timeout      ▓▓▓▓▓▓▓▓░░░░  180 ms                  ║
║                                                                ║
║                                                                ║
║       [ Uninstall ]  [ Update v2.1.1 ]  [ Edit configuration ] ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

### Spatial context for Direction A

```
┌────────────────────────────────────────────────────────────────┐
│ Main window  (dimmed 40% when Pack Detail sheet is over it)   │
│                                                                │
│   ┌─────────────────────┐                                     │
│   │ Keyboard (dimmed)   │    ┌──────────────┐                 │
│   │                     │    │ Inspector    │                 │
│   └─────────────────────┘    │ (dimmed)     │                 │
│                              └──────────────┘                 │
│                                                                │
│       ╔══════════════════════════════════════╗                │
│       ║ Pack Detail (A)                      ║                │
│       ║ — opaque, centered —                 ║  ← sheet       │
│       ║                                      ║                │
│       ║                                      ║                │
│       ║                                      ║                │
│       ╚══════════════════════════════════════╝                │
└────────────────────────────────────────────────────────────────┘

[Pack Detail is a centered sheet over a dimmed main window. The
 hero keyboard diagram lives inside the sheet. The user's real
 keyboard below is dimmed and not interactive.]
```

### Visual grammar

- Large display type for the name (SF Pro Display 32 pt semibold, tracking -1%).
- Author / version / metrics line in SF Pro Text 13 pt muted.
- Description reads as editorial copy — paragraph form, 15 pt, 65ch max width.
- **Keyboard diagram is the hero** — 480×160 pt, rendered with care. Not a schematic; an illustration.
- Binding list is a quiet second-class citizen: small bullets, 13 pt, mono-aligned.
- Quick settings are inline grouped controls.
- CTAs are bottom-right, right-aligned.

### Motion behavior

- Entry: sheet slides up (280ms). Diagram fades in first, then affected keys gain a gentle left-to-right wash of tint (600ms). Feels like the pack is "arriving" on the page.
- Quick-setting changes: no keyboard animation in the hero diagram — the diagram is *representational*, not live.
- On Install: diagram's glowing keys pulse once (200ms), sheet dismisses, main window un-dims, the **real** keyboard echoes the same pulse.

### Strengths

- **Feels like a real thing.** The pack has stature. Users treat it as a considered choice, not a throwaway.
- **Scales to community/authored packs later.** The "by X · rating" pattern accommodates a future where not every pack is first-party.
- **Description copy gets to breathe.** Copy is our differentiator — this direction lets it work.

### Risks

- **Static feel.** The hero diagram looks like a picture, not a preview. Users may not feel the connection between quick settings and their real keyboard.
- **Editorial weight can feel heavy for small packs.** A "Caps Lock → Escape" pack looks over-packaged here. May need a lighter variant, which fragments the design.
- **Hero diagrams are expensive per-pack assets.** Twelve Starter Kit packs × well-drawn diagram = significant per-pack art work. Either we produce them manually or design a parametric diagram generator — both cost effort.

### When this is right

If KeyPath's identity is "curated keyboard customization, editorial in voice, packs are products." This direction treats packs with dignity and makes them feel like things worth collecting.

---

## Direction B — "The Live Preview"

**Hypothesis:** *"A pack is a transformation. This page is a live playground that shows exactly what will happen before you commit."*

**Model:** iOS Widget customization screen. macOS wallpaper picker. Configurator patterns from design tools. The keyboard is always on; the quick settings drive it; install is a commit.

### Wireframe B-1: Pre-install state — live preview

```
╔════════════════════════════════════════════════════════════════╗
║  ← Back                                                    ✕   ║
║                                                                ║
║  Home-Row Mods                                                 ║
║  Turn your home row into modifier keys.                        ║
║                                                                ║
║  ┌──────────────────────────────────────────────────────────┐ ║
║  │                                                          │ ║
║  │    ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮             │ ║
║  │    │Q│ │W│ │E│ │R│ │T│ │Y│ │U│ │I│ │O│ │P│             │ ║
║  │    ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯             │ ║
║  │   ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮              │ ║
║  │   │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│              │ ║
║  │   │⌃│ │⌥│ │⇧│ │⌘│ │ │ │ │ │⌘│ │⇧│ │⌥│ │⌃│              │ ║
║  │   ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯              │ ║
║  │    ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮                         │ ║
║  │    │Z│ │X│ │C│ │V│ │B│ │N│ │M│                         │ ║
║  │    ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯                         │ ║
║  │                                                          │ ║
║  │     [live preview — keycaps show tap/hold labels        │ ║
║  │      and respond to hovering the quick-setting cards]   │ ║
║  └──────────────────────────────────────────────────────────┘ ║
║                                                                ║
║  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         ║
║  │ Layout       │  │ Hold timing  │  │ Active when  │         ║
║  │              │  │              │  │              │         ║
║  │ ● CAGS       │  │ ▓▓▓▓▓░░░░    │  │ Built-in     │         ║
║  │ ○ CGAS       │  │ 180 ms       │  │ keyboard ▾   │         ║
║  │ ○ Custom…    │  │              │  │              │         ║
║  └──────────────┘  └──────────────┘  └──────────────┘         ║
║                                                                ║
║  ▼ See all 8 bindings                                          ║
║                                                                ║
║                              [ Customize… ]   [ Install ]      ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

### Wireframe B-2: Hover state (user hovers "Layout: CGAS" radio)

```
╔════════════════════════════════════════════════════════════════╗
║  Home-Row Mods                                                 ║
║                                                                ║
║  ┌──────────────────────────────────────────────────────────┐ ║
║  │                                                          │ ║
║  │   ╭·╮ ╭·╮ ╭·╮ ╭·╮ ╭─╮ ╭─╮ ╭·╮ ╭·╮ ╭·╮ ╭·╮              │ ║
║  │   │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│              │ ║
║  │   │⌘│ │⌥│ │⇧│ │⌃│ │ │ │ │ │⌃│ │⇧│ │⌥│ │⌘│              │ ║  ← labels update live
║  │   ╰·╯ ╰·╯ ╰·╯ ╰·╯ ╰─╯ ╰─╯ ╰·╯ ╰·╯ ╰·╯ ╰·╯              │ ║     keycaps pulse
║  │                                                          │ ║
║  │   (affected keys briefly pulse as labels crossfade)     │ ║
║  └──────────────────────────────────────────────────────────┘ ║
║                                                                ║
║  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         ║
║  │ Layout       │  │ Hold timing  │  │ Active when  │         ║
║  │              │  │              │  │              │         ║
║  │ ○ CAGS       │  │ ▓▓▓▓▓░░░░    │  │ Built-in     │         ║
║  │ ●·CGAS·      │  │ 180 ms       │  │ keyboard ▾   │         ║  ← hovered card
║  │ ○ Custom…    │  │              │  │              │         ║     highlighted
║  └──────────────┘  └──────────────┘  └──────────────┘         ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

### Wireframe B-3: Post-install

```
╔════════════════════════════════════════════════════════════════╗
║  Home-Row Mods                              ✓ Installed    ✕   ║
║  ────────────────────────────                                  ║
║                                                                ║
║  ┌──────────────────────────────────────────────────────────┐ ║
║  │  [preview keyboard still here, still live —              │ ║
║  │   user can still tweak and see changes]                  │ ║
║  └──────────────────────────────────────────────────────────┘ ║
║                                                                ║
║  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         ║
║  │ Layout       │  │ Hold timing  │  │ Active when  │         ║
║  │ ● CAGS       │  │ ▓▓▓▓▓░░░░    │  │ Built-in ▾   │         ║
║  └──────────────┘  └──────────────┘  └──────────────┘         ║
║                                                                ║
║  [ Uninstall ]          [ Customize… ]    [ Save changes ]    ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

### Spatial context for Direction B

```
┌────────────────────────────────────────────────────────────────┐
│ Main window  (dimmed 40%)                                      │
│                                                                │
│   ┌─────────────────────┐    ┌──────────────┐                 │
│   │ Keyboard (dimmed)   │    │ Inspector    │                 │
│   └─────────────────────┘    └──────────────┘                 │
│                                                                │
│       ╔══════════════════════════════════════╗                │
│       ║ Pack Detail (B)                      ║                │
│       ║ — opaque, centered —                 ║                │
│       ║  contains its own live keyboard      ║  ← sheet       │
│       ║  that is the focus of attention      ║                │
│       ║                                      ║                │
│       ╚══════════════════════════════════════╝                │
└────────────────────────────────────────────────────────────────┘

[Like Direction A: centered sheet over dimmed main window. But
 Pack Detail B contains an interactive keyboard diagram inside
 it. The user's real keyboard below is dimmed and ignored.]
```

### Visual grammar

- Smaller, functional type. Pack name 20 pt semibold (not display size). Description 13 pt, one or two lines max.
- Keyboard diagram is the **center of gravity** — larger than Direction A's hero, and *interactive*.
- Quick settings as **card-style panels** in a three-across row. Each card is a self-contained control group. Hovering the card previews its effect on the keyboard.
- Binding list is collapsed behind a disclosure — reachable but not taking up space.
- CTAs bottom-right.

### Motion behavior

- Entry: diagram renders first; quick-setting cards fade in staggered (80ms per card).
- Hover over a quick-setting card → relevant keys on the diagram glow for the duration of the hover.
- Changing a setting → keys crossfade their labels; affected keys pulse once (150ms).
- Changing the slider timing → affected keys show a brief animation whose duration mirrors the timing value (fast timing = fast animation, slow timing = slow animation). Teaches the user what the number means.
- On Install: the whole diagram does a single confident pulse; sheet dismisses; the real keyboard's matching keys echo the pulse once.

### Strengths

- **Teaches by doing.** A user who doesn't know what "CAGS" means learns in two hovers.
- **Quick settings are primary, not secondary.** Encourages tweaking without ever needing Customize…
- **Transformational nature is explicit.** You see what will change, not a picture of what exists.

### Risks

- **Less confident, more utilitarian.** The pack feels like a configurator, not a considered thing. Casual browsers may not form an emotional attachment.
- **Complex packs don't fit.** A Vim-nav pack that introduces a layer can't be previewed on a flat keyboard — it's layer-dependent. Needs a fallback mode, which fragments the design.
- **Redundancy with the real keyboard.** The user's actual keyboard is below the sheet, also a keyboard — we now have two keyboards visible on install. Conceptually odd.
- **Fiddly risk.** Packs with 3+ quick settings start to feel like a dashboard. Needs tight restraint.

### When this is right

If KeyPath's identity is "exploratory, hands-on — see before you commit." This direction treats packs as *adjustable things* rather than *curated things*.

---

## Direction C — "The In-Place Modification"

**Hypothesis:** *"A pack isn't a separate thing — it's a modification to the user's existing keyboard. This page should keep the user's actual keyboard visible while the pack is being evaluated."*

**Model:** macOS Stage Manager mid-preview. Figma plugin-action preview. Xcode's assistant editor. A surface that never fully takes over, because the main thing (the user's real keyboard) should stay the frame of reference.

### Wireframe C-1: Pre-install — panel with user's keyboard visible

```
┌────────────────────────────────────────────────────────────────┐
│ Main window                                                    │
│                                                                │
│  ╭─╮ ╭·╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮          │
│  │`│ │1│ │2│ │3│ │4│ │5│ │6│ │7│ │8│ │9│ │0│ │-│ │=│          │
│  ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯          │
│  ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮          │
│  │⇥│ │Q│ │W│ │E│ │R│ │T│ │Y│ │U│ │I│ │O│ │P│ │[│ │]│          │
│  ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯          │
│  ╭─╮ ╭·╮ ╭·╮ ╭·╮ ╭·╮ ╭─╮ ╭─╮ ╭·╮ ╭·╮ ╭·╮ ╭·╮ ╭─╮              │
│  │⇪│ │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│ │'│              │
│  │ │ │⌃│ │⌥│ │⇧│ │⌘│ │ │ │ │ │⌘│ │⇧│ │⌥│ │⌃│ │ │              │
│  ╰─╯ ╰·╯ ╰·╯ ╰·╯ ╰·╯ ╰─╯ ╰─╯ ╰·╯ ╰·╯ ╰·╯ ╰·╯ ╰─╯              │
│  ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮                  │
│  │⇧│ │Z│ │X│ │C│ │V│ │B│ │N│ │M│ │,│ │.│ │/│                  │
│  ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯                  │
│                       ╭────────────────╮                       │
│                       │     Space      │                       │
│                       ╰────────────────╯                       │
│                                                                │
│  [user's actual keyboard — affected keys glow with pending    │
│   tint and pending tap/hold labels; unaffected keys normal.   │
│   Whole canvas dims to 90% to push attention toward panel]    │
│                                                                │
│                                                                │
│                           ╔═══════════════════════════════╗   │
│                           ║                           ✕   ║   │
│                           ║  Home-Row Mods                ║   │
│                           ║  ─────────────                ║   │
│                           ║                               ║   │
│                           ║  Turn your home row into      ║   │
│                           ║  modifier keys.               ║   │
│                           ║                               ║   │
│                           ║  Will modify 8 keys:          ║   │
│                           ║  a s d f j k l ;              ║   │
│                           ║  (highlighted above →)        ║   │
│                           ║                               ║   │
│                           ║  Quick settings               ║   │
│                           ║                               ║   │
│                           ║  Hold timeout                 ║   │
│                           ║  ▓▓▓▓▓▓░░░░  180 ms           ║   │
│                           ║                               ║   │
│                           ║  Layout                       ║   │
│                           ║  ● CAGS    ○ CGAS             ║   │
│                           ║                               ║   │
│                           ║  Active on                    ║   │
│                           ║  [ Built-in keyboard  ▾ ]     ║   │
│                           ║                               ║   │
│                           ║                               ║   │
│                           ║  [ Customize… ]  [ INSTALL ]  ║   │
│                           ╚═══════════════════════════════╝   │
└────────────────────────────────────────────────────────────────┘

[Panel is ~440 pt wide, anchored right-of-center. Main window
 keyboard is left visible but dimmed. Affected keys (a/s/d/f/
 j/k/l/;) are glowing with pending tint on the real keyboard,
 not on any mini-diagram.]
```

### Wireframe C-2: User changes "Layout" to CGAS → real keyboard updates live

```
┌────────────────────────────────────────────────────────────────┐
│  ╭─╮ ╭·╮ ╭·╮ ╭·╮ ╭·╮ ╭─╮ ╭─╮ ╭·╮ ╭·╮ ╭·╮ ╭·╮ ╭─╮              │
│  │⇪│ │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│ │'│              │
│  │ │ │⌘│ │⌥│ │⇧│ │⌃│ │ │ │ │ │⌃│ │⇧│ │⌥│ │⌘│ │ │              │  ← labels
│  ╰─╯ ╰·╯ ╰·╯ ╰·╯ ╰·╯ ╰─╯ ╰─╯ ╰·╯ ╰·╯ ╰·╯ ╰·╯ ╰─╯              │     crossfade live
│                                                                │
│                                                                │
│                           ╔═══════════════════════════════╗   │
│                           ║  Home-Row Mods                ║   │
│                           ║                               ║   │
│                           ║  Layout                       ║   │
│                           ║  ○ CAGS    ● CGAS             ║   │ ← user picked CGAS
│                           ║                               ║   │
│                           ║  [ Customize… ]  [ INSTALL ]  ║   │
│                           ╚═══════════════════════════════╝   │
└────────────────────────────────────────────────────────────────┘

[The real keyboard's hold labels crossfade from CAGS to CGAS
 in 180ms. No mini-diagram anywhere — the real keyboard IS the
 preview. User sees exactly what their keyboard will look like
 post-install, in full fidelity.]
```

### Wireframe C-3: User clicks Install — continuity, not a cut

```
┌────────────────────────────────────────────────────────────────┐
│  ╭─╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭─╮ ╭─╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭▓╮ ╭─╮              │
│  │⇪│ │A│ │S│ │D│ │F│ │G│ │H│ │J│ │K│ │L│ │;│ │'│              │
│  │ │ │⌘│ │⌥│ │⇧│ │⌃│ │ │ │ │ │⌃│ │⇧│ │⌥│ │⌘│ │ │              │
│  ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯              │
│                                                                │
│  [panel dismisses over 220ms — affected keys' "pending"       │
│   tint (··) transitions to "installed" tint (▓▓) over 240ms,  │
│   no flash, no cut. The keys that pulsed during preview are   │
│   simply now permanent. Install felt like continuity, not     │
│   like a commit point.]                                        │
│                                                                │
│                                                                │
│  ┌────────────────────────────────────────────────┐           │
│  │  ✓ Home-Row Mods installed · 8 bindings added  │  [Undo]   │
│  └────────────────────────────────────────────────┘           │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Wireframe C-4: Post-install, Pack Detail revisited

```
┌────────────────────────────────────────────────────────────────┐
│  [same real keyboard — now showing installed tint (▓▓) on     │
│   affected keys, which is the new steady state]               │
│                                                                │
│                           ╔═══════════════════════════════╗   │
│                           ║                           ✕   ║   │
│                           ║  Home-Row Mods                ║   │
│                           ║                  ✓ Installed  ║   │
│                           ║  ─────────────                ║   │
│                           ║                               ║   │
│                           ║  Turn your home row into      ║   │
│                           ║  modifier keys.               ║   │
│                           ║                               ║   │
│                           ║  Active on 8 keys             ║   │
│                           ║  (highlighted on keyboard)    ║   │
│                           ║                               ║   │
│                           ║  Quick settings               ║   │
│                           ║  Hold timeout                 ║   │
│                           ║  ▓▓▓▓▓▓░░░░  180 ms           ║   │
│                           ║                               ║   │
│                           ║  Layout                       ║   │
│                           ║  ○ CAGS    ● CGAS             ║   │
│                           ║                               ║   │
│                           ║  [ Uninstall ]                ║   │
│                           ║              [ Save changes ] ║   │
│                           ╚═══════════════════════════════╝   │
└────────────────────────────────────────────────────────────────┘

[Panel shows installed state. Keyboard in background shows
 installed tint. Changing a quick setting updates the real
 keyboard in real time. Uninstall flow: clicking Uninstall
 dims the affected keys back to default over 280ms while the
 panel transitions out.]
```

### Wireframe C-5: The Gallery-standalone fallback (see §"When C won't work")

When Pack Detail is invoked from inside the Gallery sheet (which covers the main window), there's no visible keyboard to modify. C's core pattern doesn't apply. In this case, Pack Detail falls back to a Direction-A-style **contained** layout:

```
╔════════════════════════════════════════════════════════════════╗
║                                                            ✕   ║
║                                                                ║
║       HOME-ROW MODS                                            ║
║       ─────────────                                            ║
║       by KeyPath Team  ·  v2.1.0                               ║
║                                                                ║
║       Turn your home row into modifier keys.                   ║
║                                                                ║
║       ┌────────────────────────────────────────────────────┐  ║
║       │ [mini keyboard diagram shown here as fallback —    │  ║
║       │  identical in spirit to Direction A, just smaller] │  ║
║       └────────────────────────────────────────────────────┘  ║
║                                                                ║
║       Will modify 8 keys. To preview changes on your own       ║
║       keyboard, close the Gallery and reopen this pack         ║
║       from the main window.                                    ║
║                                                                ║
║       Quick settings                                           ║
║       ──────────────                                           ║
║       Hold timeout      ▓▓▓▓▓▓▓▓░░░░  180 ms                  ║
║       Layout            ● CAGS     ○ CGAS                      ║
║                                                                ║
║                                                                ║
║                              [ Customize… ]   [ Install ]      ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

[One alternative: ↗ a small "Preview on my keyboard" button
 that closes the Gallery and opens the in-place panel instead.
 Engineering friction is real for this option — we'd need to
 save the Gallery's scroll state and return to it.]
```

### Spatial context for Direction C

```
┌────────────────────────────────────────────────────────────────┐
│ Main window                                                    │
│                                                                │
│   ┌───────────────────────────────────────────┐               │
│   │                                           │               │
│   │   Keyboard (dimmed to 90%,               │               │
│   │   affected keys glowing with pending tint)│               │
│   │                                           │               │
│   └───────────────────────────────────────────┘               │
│                                                                │
│                              ╔═══════════════════════════╗    │
│                              ║ Pack Detail (C)           ║    │
│                              ║ — 440 pt wide panel —     ║    │
│                              ║ anchored right-of-center  ║    │
│                              ║                           ║    │
│                              ║ no keyboard inside panel  ║    │
│                              ║ (the real one IS the      ║    │
│                              ║  preview)                 ║    │
│                              ║                           ║    │
│                              ╚═══════════════════════════╝    │
└────────────────────────────────────────────────────────────────┘

[Panel floats over main window, right-anchored, but main window
 keyboard is still visible. The affected keys on the real
 keyboard show the pending change. Panel is pure information —
 text, controls, actions. No mini-keyboard inside.]
```

### Visual grammar

- Panel is tighter than A or B. 440 pt wide (vs. 640 for sheets A/B). Less real estate because it's not carrying a keyboard diagram.
- Pack name 20 pt semibold. No hero diagram, so no display type needed.
- Description is shorter — user is primarily looking at the keyboard, not reading.
- Quick settings stack vertically inside the panel (three columns won't fit in 440 pt).
- "Will modify N keys" list is short text, not a binding table — binding table would duplicate what the real keyboard already shows.
- CTAs bottom-right of the panel.
- The **real keyboard** carries all the visual weight: the tint, the labels, the transformation. Panel is secondary.

### Motion behavior

- Entry: main window dims to 90%, panel slides in from the right (280ms spring), affected keys on the real keyboard bloom with pending tint (staggered 40ms left-to-right, 400ms total).
- Quick-setting changes: real keyboard labels crossfade in 180ms. Timing slider changes are represented on the real keyboard with a subtle ring-pulse whose duration mirrors the value.
- On Install: panel slides out (220ms), main window un-dims to 100%, affected keys' tint transitions from "pending" (··) to "installed" (▓▓) over 240ms. **No cut, no flash, no new state.** The keys the user was looking at during preview are simply now permanent.
- On Cancel / ✕: panel slides out, keys' tint fades from pending back to default (280ms). Main window returns to pre-preview state.

### Strengths

- **Most coherent with "the keyboard is the canvas."** No mini-diagram, no duplicate representation — the real keyboard IS the preview.
- **Makes transformation feel personal.** *Your* keys, right there, about to change. More emotionally direct than any diagram-in-a-sheet.
- **Install is continuous.** The keys that glowed during preview simply stay glowed. No visual discontinuity between "previewing" and "installed."
- **The "real keyboard as preview" pattern compounds.** Once built, this mechanism can be used elsewhere — scope changes, layer switches, override visualizations, uninstall previews. Pays down technical debt on future design work.

### Risks

- **Only works when the keyboard is the right reference.** If the pack installs into a non-base layer, the keyboard the user is looking at doesn't show the pending change. Needs the fallback mode (§wireframe C-5).
- **Doesn't work inside the Gallery sheet.** Gallery covers the main window. When opening Pack Detail from Gallery, the real keyboard isn't visible. Needs fallback (same §C-5).
- **Constrained panel real estate.** 440 pt is less room for editorial copy, version info, rating/install metrics. Pack authorship feels less prominent.
- **Most expensive engineering.** Requires tight coordination between the Pack Detail panel and the main window's keyboard state. Two sources of truth (preview state, installed state) that must never desync. State bugs will be real.

### When this is right

If KeyPath's identity is "the minimum abstraction between you and your keyboard." This direction has the highest conceptual purity but demands the most from the rest of the design system to stay coherent.

---

## Side-by-side comparison

| Dimension | A: Product page | B: Live preview | C: In-place modification |
|---|---|---|---|
| **What a pack feels like** | A curated thing | A configurable thing | A pending change to *your* keyboard |
| **Primary visual focus** | Editorial type + hero diagram in the sheet | Keyboard + quick settings in the sheet (coupled) | User's real keyboard; panel is supporting |
| **Emotional register** | Confident, inviting | Hands-on, exploratory | Intimate, minimalist |
| **Real keyboard during preview** | Dimmed, ignored | Dimmed, ignored | The preview itself |
| **Mini-diagram in the sheet** | Yes — hero size | Yes — live/interactive | No |
| **Post-install feels…** | Like a sheet dismissing | Like a sheet dismissing | Like a change solidifying |
| **Handles layer packs** | Fine (just more rows in bindings list) | Needs fallback — layer can't preview flat | Needs fallback — layer not visible on base |
| **Works in Gallery standalone** | Naturally | Yes, with the same sheet | **No** — requires fallback mode |
| **Implementation complexity** | Moderate | High (coupled live diagram) | Highest (panel + real keyboard state sync) |
| **Scales to user/community packs** | Best (author/metrics pattern built in) | OK | Neutral |
| **Per-pack asset cost** | High (hero diagrams) | Moderate (live diagrams can be parametric) | Low (real keyboard does the work) |
| **Compounds for future design** | Low | Low | High (real-keyboard-as-preview reusable everywhere) |
| **Coherence with "keyboard as canvas"** | Moderate | Strong (but with redundancy risk) | Strongest |
| **Risk: feels static** | High | Low | Low |
| **Risk: feels fiddly** | Low | Moderate | Moderate |
| **Risk: fragmented design** | Low (one surface for all contexts) | Moderate (layer fallback needed) | High (both layer and Gallery fallbacks) |

---

## Lead designer's recommendation

**Direction C, with a Direction-A-style fallback for the two contexts where C can't apply.**

### Why C

**It matches the product's deepest principle.** KeyPath's whole thesis is that the keyboard is the canvas. Every other direction puts a mini-representation of the keyboard *inside* a sheet, which is a small but real admission that the sheet is the primary surface and the keyboard is just content. Direction C says *no* — the keyboard is the subject, always. The panel is a tool for editing what the keyboard does. Users feel the difference immediately.

**The install moment is better.** In A and B, "installing" is a sheet dismissing and some separate confirmation animation — two events, cut together. In C, installing is a single continuous transition: the keys you were previewing simply become permanent. No flash, no cut, no new state to render. The user sees their keyboard change, and it stays changed. That's correct.

**The pattern pays dividends.** Once we build "main-keyboard-as-preview" for Pack Detail, we can use it for overrides, scope switches, layer transitions, uninstall previews, update diffs, and more. The cost is upfront; the leverage is everywhere.

**It forces discipline.** A 440 pt panel with no room for hero imagery or long editorial copy keeps pack descriptions tight. That's good. If a pack needs more room to explain itself, it's probably a pack that shouldn't exist as a single pack.

### Honest caveats

**C doesn't work everywhere.** It needs a fallback for two cases:
1. Pack Detail invoked from inside the Gallery sheet (no main window visible).
2. Pack installs into a layer the user isn't currently looking at.

I'd handle both by falling back to a **Direction-A-like contained view** (wireframe C-5). One extra component, used only in those two cases. Acceptable.

**C costs more engineering.** The panel and the real keyboard must stay in sync as quick settings change. Two sources of truth for the pending-state labels, tints, and layer scoping. State bugs will happen and must be designed for (clear error states, explicit "revert preview" if state drifts).

**C is less ready for the future where users author packs.** A's "by X · rating" header is the community pattern; C's tighter panel has less room for that. Mitigation: the Gallery-standalone fallback can carry the author/metrics weight, since that's where new users browse community content anyway.

### Why not A

A is genuinely good. If we went with A, we'd ship a product we'd be proud of. It's the safer, easier choice.

But A's core weakness is that *the hero diagram is a picture*. Users look at a picture and form a picture-of-a-picture mental model — "here's what this pack does." C's model is more direct: "here's what your keyboard becomes." The difference sounds small on paper; it's significant in use.

Also, A requires per-pack hero-diagram design work. Twelve Starter Kit packs means twelve well-drawn diagrams. Either we make them by hand (slow, expensive, inconsistent) or we build a parametric diagram generator (its own design/engineering project). C sidesteps this entirely — the real keyboard is the diagram, for every pack, free.

### Why not B

B is fun and teaches well. A user tweaking quick settings in B learns CAGS-vs-CGAS faster than in A or C.

But B positions the pack as a *configurator* — a widget to tune — not a considered thing to adopt. That reads less confident, and less Apple-like in voice. Packs should feel like things you thoughtfully collect, not gadgets you fidget with.

B also has the redundancy problem: the sheet contains a keyboard, and the real keyboard is also below it. Two keyboards in one workspace is conceptually odd, visually busy, and invites the question *"which one is real?"*

### If exec overrules and picks A or B

Totally defensible. A is the lowest-risk choice and the easiest to build. B is the most "teaching-oriented" choice and plays well with users who like to tinker. Either can be shipped with pride.

But my vote is C. It's the direction that makes KeyPath feel like *KeyPath*, not like an App Store for keyboards. That difference is worth the extra engineering work and the two fallback surfaces.

---

## What happens once a direction is picked

- Visual designer produces full-fidelity comps of the chosen direction for every state (pre-install, installing, installed/unmodified, installed/modified, update-available, fully-overridden).
- Motion designer refines the direction-specific transitions.
- Sprint 2 is planned knowing which pattern the rest of the app will echo (the inspector, override warnings, layer changes, etc. will all mirror the chosen direction's visual language).
- Any deferred work (like the Gallery-standalone fallback if we pick C) gets its own sub-section in the final spec.

The three directions are genuinely different products. Once picked, the others go into archive — not saved for comparison later, not A/B tested. Picking fast and committing is more important than picking perfectly.

---

## Open questions surfaced by this exploration

1. **If we pick C**, does the fallback need to be an actual Direction-A surface, or something lighter (e.g., a condensed dialog)? I lean: use the fallback design as a test-bed for Direction A's pattern, so we benefit from building it regardless.
2. **Pack iconography.** None of these directions require pack icons/logos. But A's header and B's cards would be enriched by them. Do packs need visual identity beyond a name?
3. **Keyboard diagram fidelity.** If we pick A or B, the visual designer needs to propose a style (schematic? illustrative? parametric?) and ideally a way to generate diagrams from pack manifests rather than draw them by hand. This is its own sub-project.
4. **Panel width for C.** 440 pt is my starting bet. If packs routinely need more room for copy, 520 pt might be better. Worth testing with long-description packs before locking.

---

**Decision requested:** A, B, or C?

Once decided, we proceed to full-fidelity comps for the chosen direction and carry that choice into the rest of Sprint 1 and all of Sprint 2.
