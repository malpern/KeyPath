# First-Run Experience

**Sprint:** 2
**Status:** Draft — designed as a moment, not a checklist
**Scope:** The first minute after a new user finishes the Installation Wizard and lands in KeyPath for the first time.

---

## Why this deserves its own doc

Every product has a first moment with a user. It's the single experience that shapes every decision after it: the user's mental model of what the product is, whether they'll trust it, what they think it's for. We get one shot.

Draft 1's first-run was specified as an *overlay tour, skippable*. That's infrastructure, not an experience. This doc replaces it with a designed moment.

The constraint I'm going to use: **sixty seconds**. If the new user, sixty seconds after the main window appears, doesn't have some concrete transformation on their keyboard *and* doesn't understand what just happened, we failed. A skippable tour doesn't deliver that; a crafted moment does.

---

## Design goals

1. **Value in sixty seconds.** The user sees their keyboard change in a real way within one minute. Not a demo, not a preview — an actual install they can undo.
2. **Teach the model, don't explain it.** The user learns "keyboard is the canvas, click a key to edit, Gallery has ready-made packs" through one path rather than reading tooltips.
3. **Low commitment.** Everything the first-run does is undoable. One install, one click-to-undo. The user can commit to nothing except trying.
4. **No modals.** The first-run is experienced through the product's own surfaces — the main window, the Gallery, the Pack Detail panel. Not through a separate onboarding shell.
5. **Graceful skip.** A user who already knows what they're doing can ignore the first-run. It doesn't block. It's an invitation.

---

## The sixty-second story

### 0s — Main window appears

The Installation Wizard has completed. KeyPath's main window is open on the user's screen for the first time.

The keyboard canvas is there, rendered in full fidelity. Every key is unbound — the canvas is the user's keyboard as-is, untouched.

The inspector (right panel) shows a welcome state. This is the first-run variant of the "no key selected" state — subtly different from the normal empty state:

```
╭─────────────────────────────────────╮
│                                     │
│    Welcome to KeyPath.              │
│                                     │
│    Your keyboard is on the left.    │
│    Every key is exactly how it came │
│    from Apple.                      │
│                                     │
│    Two ways to start:               │
│                                     │
│    1. Click any key to remap it.    │
│       (Simplest: try Caps Lock →    │
│        Escape — a classic.)         │
│                                     │
│    2. Browse packs — collections    │
│       of mappings curated for       │
│       common needs.                 │
│       [ Open Gallery → ]            │
│                                     │
│                                     │
│    Anything you do here is          │
│    undoable with ⌘Z.                │
│                                     │
╰─────────────────────────────────────╯
```

Nothing else is asked of them. No modal. No tour. No "click next."

### 0–15s — Two paths diverge (both teach the model)

Users split between two behaviors here:

**Path A — they click a key.** Say they click `caps` because that's the example highlighted in the welcome copy.

The welcome copy dissolves. The inspector animates into its standard "bound key — unbound on this layer" state, with the "Popular for this key" section filled in for `caps`:

```
╭─────────────────────────────────────╮
│   ┌─────┐                           │
│   │ ⇪   │   Caps Lock               │
│   └─────┘   on base layer           │
│                                     │
│   ── Output ───────────────────     │
│   [ Record output ]                 │
│   [ Type...       ]                 │
│                                     │
│   ── Popular for this key ────      │
│   [ Caps Lock → Escape  → ]         │
│   [ Caps Lock as Hyper  → ]         │
│   [ Caps Lock as Layer  → ]         │
│   [ Browse Gallery →      ]         │
│                                     │
╰─────────────────────────────────────╯
```

They see three preset chips. No tour, but the inspector is *showing them* that packs exist. The "Caps Lock → Escape" chip is the most inviting — it matches what the welcome copy suggested.

**Path B — they click "Open Gallery" from the welcome copy.** The Gallery sheet slides up. The Discover tab is showing, and because they have 0 packs installed, the **Starter Kit section is prominent at the top**:

```
╭─────────────────────────────────────────────╮
│ Gallery                                  ✕   │
│                                             │
│ ┌─[ Discover ]─ Categories ─ My Packs ─┐   │
│                                             │
│  Start here                                 │
│  ────────────                               │
│  New to keyboard customization? These       │
│  three packs are good places to begin.      │
│                                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │ Caps →  │  │ Home-   │  │ Smart   │     │
│  │  Escape │  │  row    │  │  Quotes │     │
│  │         │  │  mods   │  │         │     │
│  └─────────┘  └─────────┘  └─────────┘     │
│                                             │
│  Collections                                │
│  ────────────                               │
│  ...                                        │
╰─────────────────────────────────────────────╯
```

Same three Starter Kit packs the inspector was suggesting. The product has a coherent voice across surfaces.

### 15–30s — They pick "Caps Lock → Escape"

Whichever path they took, clicking the chip or card opens Pack Detail (Direction C).

The Gallery sheet (if it was open) dismisses in favor of Pack Detail. The user's real keyboard is now visible below/behind the Pack Detail panel, and `caps` is glowing with the **pending-change tint**:

```
┌─────────────────────────────────────────────┐
│ [main window keyboard — dimmed 90%]         │
│                                             │
│  ╭·╮ ╭─╮ ╭─╮ ╭─╮ ...                        │
│  │⇪│ │Q│ │W│ │E│                            │
│  │·│                                        │
│  ╰·╯  ← caps is glowing (pending)           │
│                                             │
│                                             │
│                 ╔══════════════════════╗    │
│                 ║ Caps Lock → Escape   ║    │
│                 ║                      ║    │
│                 ║ A useful key where   ║    │
│                 ║ Caps Lock used to    ║    │
│                 ║ be.                  ║    │
│                 ║                      ║    │
│                 ║ Will change 1 key:   ║    │
│                 ║ ⇪ (highlighted       ║    │
│                 ║ above →)             ║    │
│                 ║                      ║    │
│                 ║ [Customize…][INSTALL]║    │
│                 ╚══════════════════════╝    │
└─────────────────────────────────────────────┘
```

They see:
- A pack with value-first copy ("A useful key where Caps Lock used to be.").
- The specific key that will change, glowing on their real keyboard.
- A primary Install action.
- No jargon. No timeout sliders (this pack has no quick settings). No demands.

### 30–45s — They click Install

```
┌─────────────────────────────────────────────┐
│ [main window keyboard]                      │
│                                             │
│  ╭▓╮ ╭─╮ ╭─╮ ╭─╮                            │
│  │⇪│ │Q│ │W│ │E│                            │
│  │▓│                                        │
│  ╰▓╯  ← caps glows permanently now (install)│
│                                             │
│  [panel dismissed over 220ms — the caps     │
│   key's pending tint transitions to         │
│   installed tint over 240ms, no flash]      │
│                                             │
│  ┌────────────────────────────────────┐     │
│  │ ✓ Caps Lock → Escape installed.    │     │
│  │   Caps Lock now presses Escape.    │     │
│  │                           [ Undo ] │     │
│  └────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

The toast includes the concrete consequence — *"Caps Lock now presses Escape"* — not just the pack name. The user knows exactly what their keyboard now does.

The Undo button gives them a zero-risk exit.

### 45–60s — They actually try it

This is the moment we're aiming for. They press Caps Lock on their physical keyboard. Escape happens.

We don't design this part — macOS does. But we've set them up: the welcome copy suggested trying the simplest possible remap; the pack they installed is that remap; the toast told them what to expect; now they press the key and the expectation matches reality.

This is the thing people will tell a friend about. Not the Gallery UI, not the inspector design, not the visual polish. The *"I pressed Caps Lock and Escape happened"* moment. Every other design decision in the product exists to make this moment possible and reliable.

---

## What they've learned in sixty seconds

Without any tour, without any modal, without any explicit instruction:

- **The keyboard is the canvas.** It's the first thing they saw, it's where their attention went, it's where the change happened.
- **Clicking a key opens the inspector.** They did this (or saw the inspector change state when offered).
- **The Gallery exists and it's curated.** They saw the Starter Kit section — "Start here" — branded as welcome content for new users.
- **Packs are concrete changes.** They installed one, saw the specific key change, felt the change under their fingers. Not abstract "rule collections" or "configurations" — an actual transformation.
- **Everything is undoable.** The toast said Undo; ⌘Z works; the welcome copy said so explicitly.

None of this was taught. It was experienced.

---

## What happens if the user skips

Two kinds of skipping:

**Skip-by-ignoring.** User dismisses the welcome copy (or it auto-fades after 30 seconds of inactivity) without clicking anything. Inspector reverts to its standard "no key selected" empty state. Starter Kit is still prominent in the Gallery whenever they eventually open it. No sense of having "missed" the onboarding.

**Skip-by-action.** User clicks a key that isn't `caps`, or opens the Gallery and browses past Starter Kit, or records a direct remap without going through a pack. All fine. The welcome copy vanishes as soon as any real action is taken. The Gallery's Starter Kit section persists until the user has installed ≥3 packs (then it auto-hides from Discover — it's served its purpose).

---

## What about users who've installed KeyPath before on another Mac?

They come back for the second time, say on a new Mac. Do they want the sixty-second story? Probably not.

Detection: we can't reliably tell if someone is truly new vs returning without account sync (which isn't shipping in v1). But the welcome copy is harmless if seen by an experienced user — it's not a tour, it's just an empty-state with two CTAs. An experienced user will quickly click Open Gallery or click a key and move on; the welcome dissolves.

So: no detection logic in v1. The welcome is always shown on empty keyboard. It's light enough that returning users aren't annoyed.

---

## Copy specifics (pressure-tested against editorial voice guide)

### Welcome inspector copy

*"Welcome to KeyPath."*

*"Your keyboard is on the left. Every key is exactly how it came from Apple."*
— States the pain (the keyboard is unmodified) and the starting place. Concrete.

*"Two ways to start:"*

*"1. Click any key to remap it. (Simplest: try Caps Lock → Escape — a classic.)"*
— Offers the primary path with a concrete, famous example. Anchor that even non-hobbyists have heard.

*"2. Browse packs — collections of mappings curated for common needs. [Open Gallery →]"*
— Offers the secondary path with a value-framed description of what a pack is.

*"Anything you do here is undoable with ⌘Z."*
— Reassurance. Not hidden in a help doc.

### Starter Kit section title + intro

*"Start here"*
*"New to keyboard customization? These three packs are good places to begin."*
— No "Recommended for you" (no personalization in v1). No "Featured" (no editorial claim). Just: these are good for a new user.

### Install toast for the specific "Caps Lock → Escape" case

*"Caps Lock → Escape installed. Caps Lock now presses Escape. [Undo]"*
— The pack name + the concrete consequence + the undo.

### Install toast for multi-key packs (for comparison)

*"Home-Row Mods installed · 8 bindings added. [Undo]"*
— Pack name + count (since enumerating 8 bindings in a toast is unreadable). User can click the toast to see what changed in detail.

---

## When the user's first action is NOT a Starter Kit pack

Say they click `caps` directly and record `Escape` as output (a direct mapping, no pack involved). That's a valid first-run path too. The moment still works:

1. They click Caps Lock.
2. Inspector shows the record state.
3. They press Escape on their keyboard.
4. Inspector updates; keyboard canvas shows Caps Lock as bound.
5. Toast: *"Caps Lock now presses Escape. [Undo]"*
6. They press Caps Lock physically → Escape happens.

Same sixty-second outcome, different surface path. The product is coherent either way. What they missed: the Gallery's existence. But that's recoverable — the inspector's "Popular for this key" block and the "Add from Gallery" toolbar button both lead there, and they'll stumble into Gallery eventually.

---

## What we explicitly don't do in first-run

Per the earlier exec direction to not generate visibility or engagement:

- **No "pro tip" pop-ups** after first install.
- **No progress meter** ("1/10 mappings recommended to unlock KeyPath's potential!"). Gamification is off the table.
- **No email capture** or account creation prompt.
- **No suggested next action** beyond what the inspector already offers in its standard state.
- **No achievement or reward** for reaching sixty seconds.

The first-run is a door opening. Once the user is through, they're a user, not a funnel-occupant.

---

## Accessibility

- The welcome copy is screen-reader-first navigable. VoiceOver reads the welcome as a region, announces the two options, and lets the user tab to either CTA.
- Reduce Motion: the transitions between welcome-state and bound-state in the inspector are crossfades, not slides.
- High Contrast: welcome copy uses the standard text hierarchy (no custom tints that wash out).
- Keyboard-only: every first-run action is reachable via keyboard. User can open Gallery via ⌘G (or whatever binding we choose for it), click a key by Tab/arrow-key navigating the canvas.

---

## Open questions

1. **Does the welcome copy persist, or auto-fade?** Proposal: persists until first user action. Auto-fade feels artificial and risks vanishing before the user has read it. Let the user dismiss it by acting.

2. **Starter Kit section — exactly three packs or "a few"?** Fixed three is crisp. A row of 3–5 is more editorial but has variable layout. My lean: fixed three for v1. Reassess after observing use.

3. **The "try Caps Lock → Escape" nudge.** It's in the welcome copy as a concrete suggestion. Is it too prescriptive? Do we risk everyone having the same first mapping? My take: that's fine — it's the right first mapping for most people; if a user has a different idea, they'll follow their idea. But worth a review.

4. **Language for the Undo toast.** "Caps Lock → Escape installed. Caps Lock now presses Escape." is 60 characters. Too long for some toast sizes. Fallback: "Caps Lock now presses Escape." (43 chars) without the pack name, since the key transformation is more meaningful to a new user than the pack identity.

---

## Related

- Editorial Voice: [`../sprint-1/editorial-voice.md`](../sprint-1/editorial-voice.md) — the welcome copy follows the value-first pattern.
- Starter Kit: [`../sprint-1/starter-kit.md`](../sprint-1/starter-kit.md) — defines the Caps Lock → Escape pack that's the primary first-run vehicle.
- Pack Detail C: [`../sprint-1/pack-detail-directions.md`](../sprint-1/pack-detail-directions.md) — the install moment inherits from the chosen direction.
- Inspector states: [`inspector-edge-states.md`](inspector-edge-states.md) — the welcome inspector is a first-run variant of State 1.
