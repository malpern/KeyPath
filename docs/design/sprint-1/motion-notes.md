# Motion Notes — Sprint 1

**Sprint:** 1 · Day 9
**Status:** Partial — full motion spec pends Pack Detail direction
**Scope:** Motion decisions that are independent of which Pack Detail direction is picked.

---

## Principles (for this sprint and the whole product)

1. **Motion teaches, or it shouldn't be there.** Every animation either reveals structure, confirms an action, or shows continuity. Decorative motion is cut.
2. **The keyboard is real.** Motion on keys should feel like physical feedback — a pulse, a press, a glow. Not like widgets animating.
3. **Sheets are light.** Presentations are 250–300ms. Nothing slower. Fast on entry; faster on dismiss. The user should never feel they're waiting for the UI to catch up.
4. **Reduce Motion is respected everywhere.** Every animation in this doc has a spelled-out Reduce Motion fallback. No exceptions.

---

## Decisions independent of Pack Detail direction

### Gallery sheet presentation

- **Entry:** Slide up from the bottom of the main window. Duration 280ms, curve `cubic-bezier(0.2, 0.8, 0.2, 1)` (a fast-start, gentle-settle easing — feels responsive).
- **Backdrop dim:** Main window dims to 35% black overlay over the same 280ms, slightly faster curve (starts dimming at 0ms, fully dimmed by 220ms).
- **Exit:** Slide down, duration 220ms, ease-in. Backdrop lightens in parallel, fully lit at 180ms.
- **Reduce Motion:** Crossfade only, 200ms both directions. No translation.

### Tab switching within the Gallery

- **Tab indicator:** Slides to the new tab. 180ms, ease-out-quad. No content wipe.
- **Content swap:** The content area crossfades: outgoing fades out (100ms), incoming fades in (160ms), 40ms overlap. The content is short enough that a hard swap would feel harsh, but long enough that a full slide would feel slow.
- **Reduce Motion:** Instant swap; no indicator slide.

### Pack card hover and press

- **Hover in:** Card elevates (shadow 2 → 10 pt blur), scales to 1.02, 180ms spring (response 0.4, damping 0.85).
- **Hover out:** Reverse, 140ms ease-out.
- **Press (mousedown):** Quick scale-down to 0.98 over 100ms, ease-in.
- **Press release:** Return to 1.02 (if still hovered) or 1.00 (if cursor left), 120ms spring.
- **Click to open Pack Detail:** At click release, the card maintains its 1.02 scale briefly (80ms) as the Pack Detail sheet begins its entrance — provides a sense of the card "handing off" to the detail page.
- **Reduce Motion:** Shadow change only, no scale.

### Starter Kit cards (Discover tab)

Identical behavior to pack cards. No distinguishing motion — Starter Kit is content, not a feature.

### Search input

- **Focus:** Border color transitions to accent, 120ms ease-out.
- **Typing (results appearing):** Results list fades in as a group, 150ms, with a subtle 4-pt translate-up. Children do not animate individually — the whole results area is one unit.
- **Clear search (Esc):** Results fade out, 100ms. Very fast — clearing should feel snappy.
- **Reduce Motion:** No translations. Just opacity changes, same durations.

### Install toast

- **Entry:** Slides up from 40 pt below its final position, 280ms spring (response 0.5, damping 0.8). Slight overshoot permitted (up to 4 pt).
- **Dwell:** 4 seconds at full opacity and position.
- **Exit:** Fades out, 400ms ease-in. No translation — staying in place while fading makes the disappearance feel gentle, not flinched.
- **Undo tap:** Toast dismisses immediately (80ms fade). Undo action runs.
- **Reduce Motion:** Fade in, 180ms; dwell unchanged; fade out, 400ms.

### Uninstall keyboard animation

When a pack is uninstalled, affected keys on the main window fade from bound → unbound state.

- **Per-key fade:** 280ms ease-in-out.
- **Stagger:** Keys fade in the reverse order they pulsed on install (right-to-left if install was left-to-right). 30ms stagger between keys — faster than install, because uninstall should feel like retraction, not a moment.
- **Reduce Motion:** All keys fade simultaneously, 200ms.

### Update available indicator

When a pack update becomes available and the user is viewing Pack Detail or My Packs:

- **Badge/pill appearance:** 180ms scale-up from 0.5 → 1.0 with 60ms delay after the surface is shown. Prevents the user from "missing" the badge because it animated while their eye was elsewhere.
- **Reduce Motion:** Instant appearance.

---

## Motion that depends on Pack Detail direction (to be refined)

These are stubs. Full spec happens after the direction decision.

### Sheet entry for Pack Detail

- **Direction A (Product Page):** Sheet slides from right (if invoked from Gallery sheet) or from a point-of-origin near the inspector chip (if invoked from the inspector). Duration 280ms spring.
- **Direction B (Live Preview):** Same entry; diagram settles in first, quick-setting cards stagger-in over 400ms after the sheet lands.
- **Direction C (In-Place Modification):** Entry is substantially different — panel slides in, main window dims, keys on the real keyboard bloom. Full storyboard in the locked-direction spec.

### Key-pulse / install cascade

- **Direction A:** Keys on the hero diagram pulse left-to-right, 40ms stagger, 300ms per key. When user clicks Install, the sheet dismisses and the main keyboard's matching keys echo the pulse (another pass, same direction).
- **Direction B:** Similar to A but the pulse is driven by hovering each quick setting — user can "preview" before committing. On Install, a final confirming pulse.
- **Direction C:** No separate pulse; the keys on the real keyboard are *already* visually highlighted (as pending). On Install, the highlight just becomes permanent — a soft fade from "pending" to "installed" styling over 240ms. Arguably the most elegant, definitely the most dependent on getting the pending-state color right.

### Quick-setting changes

- **Direction A:** Quick settings update silently. No animation on the diagram — diagram is representational, not live.
- **Direction B:** Quick settings drive live updates on the embedded diagram. Label crossfades (180ms), tint shifts (200ms).
- **Direction C:** Quick settings drive live updates on the user's real keyboard. Same transitions as Direction B, on the real keyboard instead of the preview.

---

## Cross-cutting: pack-member highlight on the main keyboard

When a user hovers or selects a key that's part of an installed pack, the other pack members gain a subtle outline.

- **Fade in:** 120ms ease-out. Outline thickness 1 pt → 1 pt (no growth — just color appears). Accent color at 40% opacity.
- **Fade out:** 200ms ease-in. Slower than in, because the *absence* of information is less urgent than the presence of it.
- **Selection-change to another pack:** The old pack's outlines fade out over 80ms, then the new pack's outlines fade in over 120ms. A 40ms gap avoids a visually confusing "swap" where multiple outlines are half-visible on different keys.
- **Reduce Motion:** Instant appearance and disappearance of outlines.

---

## Cross-cutting: recording input on a key

When the user clicks "Record output" and the app is listening for a key press:

- **Target keycap:** Gains a pulsing accent-color border. Period 1.2s (slow breathing — not urgent). Border 1 → 2 → 1 pt.
- **Other keycaps:** Slightly dimmed (80% opacity) to focus attention.
- **Cancel (Esc or timeout):** Returns to default over 180ms.
- **Capture:** Pulse stops; the captured key briefly flashes (150ms) to confirm; then both the target and captured keys update to their new state.
- **Reduce Motion:** No pulse; target keycap gains a static 2-pt accent border. Confirmation flash replaced with a 150ms tint change.

---

## Timing ladder (reference for all durations used in the product)

A consistent timing ladder makes the app feel coherent. All motion in the product should pick from this ladder unless there's a specific reason not to.

| Token | Duration | Use case |
|---|---|---|
| **Instant** | 0ms | State changes that don't need to be felt (checkbox toggle, keyboard shortcut activation) |
| **Quick** | 100–120ms | Focus changes, immediate feedback (press, hover in) |
| **Standard** | 180–220ms | Most UI transitions (fades, tab changes, small element entries) |
| **Sheet** | 280–300ms | Large surface presentations (Gallery, Pack Detail) |
| **Slow** | 400ms | Dismissals that should feel gentle (toast fade-out), long fades |
| **Stagger base** | 30–40ms per unit | Cascading animations (install pulse, uninstall fade) |

Anything outside this ladder needs justification.

---

## What's not in scope for Sprint 1 motion

- First-run / onboarding motion (Sprint 2).
- Layer-switching motion on the main keyboard canvas (Sprint 2 — depends on layers × packs design).
- Override warning animation (Sprint 2 — depends on pack coherence design).
- Customize sheet transitions (Sprint 2).
- Error and loading states inside Pack Detail (Sprint 2).

---

**Open for review:** Anything in this doc that conflicts with exec direction or engineering constraints, flag now. Full Pack-Detail-dependent motion waits for the direction decision.
