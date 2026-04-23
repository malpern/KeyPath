# Editorial Voice — Copy guide for packs and Gallery

**Sprint:** 1 · Day 8
**Status:** Revised — aligned with existing help-content pattern
**Applies to:** All user-facing copy in the Gallery, Pack Detail pages, pack descriptions, toasts, inline messaging, and first-run guidance (Sprint 2).

---

## Why this matters

Per exec direction, we don't generate visibility for packs via featured modules, trending signals, or recommendations. That puts more weight on *copy*. If every pack has the right words around it, users can discover and decide without algorithmic help.

Copy is the cheapest place to add value and the easiest place to waste it.

---

## The shape that already works — and we must keep using

KeyPath's help docs already land this pattern well. Every help article leads with the **user goal**, not the feature name. It's also the content hierarchy codified in CLAUDE.md ("User goals and problems first"). Gallery pack copy should follow the same rule.

Two examples from the shipped help content:

> **Shortcuts Without Reaching**
>
> Every keyboard shortcut on your Mac requires a modifier — Command, Shift, Control, Option. Those keys are tucked into the bottom corners of your keyboard, forcing your fingers off the home row dozens of times an hour. Over a full workday, that's thousands of small reaches that slow you down and strain your hands.
>
> Home row mods fix this by putting modifiers right under your fingertips…

— `home-row-mods.md`. Title is the user's goal. First paragraph names the pain the user already has. The mechanism ("home row mods") is introduced only after the reader knows why they'd want one.

> **One Key, Multiple Actions**
>
> A standard keyboard gives you about 80 keys, and each one does exactly one thing. That's limiting — you run out of convenient shortcuts fast, especially if you want to launch apps, navigate, and use modifiers without leaving the home row.
>
> KeyPath lets a single key do different things depending on *how* you press it…

— `tap-hold.md`. Same shape. The title is a capability-framed goal, not the technical name ("Tap-Hold").

**The rule that governs this:** name the goal. Lead with the pain. Describe the transformation. Then, and only then, explain the mechanism.

---

## Structure for pack copy — three layers

Every pack has copy at three levels of depth. Each level tells the same story at a different length.

### Layer 1 — Card description (≤ 60 characters, one line)

A single-line framing of **the value**, not the mechanism. Goes on pack cards in the Gallery.

**Good (value-framed):**
- *"Every shortcut, without leaving the home row."*
- *"A useful key where Caps Lock used to be."*
- *"Write cleaner prose without reaching for symbols."*

**Bad (mechanism-framed — what we had before the revision):**
- *"Hold home-row keys as modifiers."*
- *"Tap caps for escape, hold for ⌃⌥⇧⌘."*
- *"Smart quotes and em-dash conversion."*

The mechanism version isn't *wrong* — it's just useless to a new user who doesn't know why any of those words matter.

### Layer 2 — Pack Detail short description (≤ 160 characters, 1–2 sentences)

The elevator pitch that lands on the Pack Detail page under the pack name. **Names the pain, then the transformation. Still no mechanism.**

Same three-sentence shape as the help docs' opening paragraph:

1. **Sentence 1 — the pain:** the situation the user already lives in, even if they hadn't named it.
2. **Sentence 2 — the change:** what their keyboard becomes after installing.

**Example:**
*"Keyboard shortcuts make you reach for the corners of your keyboard hundreds of times a day. This pack puts Control, Option, Shift, and Command right under your fingertips — every shortcut becomes a single, fluid motion from the home row."*

The word "home row" appears, but only as a concrete noun ("the home row"), not as a technical term. The pack's mechanism (tap vs. hold) isn't mentioned here at all.

### Layer 3 — Pack Detail long description (1–2 short paragraphs, ≤ 120 words)

The deeper explanation. **Now** the mechanism shows up, alongside trade-offs and what to expect in week one.

Structure:

1. **Paragraph 1 — the same pain, but deeper.** Give the reader a moment to recognize themselves. Two or three sentences that expand on the "why."
2. **Paragraph 2 — how it works and what to expect.** Introduce the tap-vs-hold or layer concept inline. Acknowledge the learning curve. Concrete promise about the other side.

**Example (home-row mods):**

*"Modifier keys — ⌘, ⌥, ⇧, ⌃ — live at the corners of your keyboard, forcing you to reach or curl your fingers to press them. Every time you use a shortcut, your hands move away from the home row. That's thousands of small movements a day that slow you down and, for some people, eventually hurt.*

*This pack assigns a modifier to each of a, s, d, and f, mirrored on j, k, l, and ;. Tap a key normally and you get the letter. Hold it briefly and it acts as a modifier. There's a short learning curve — expect a week of adjusting to the new rhythm — but the payoff is typing every shortcut without ever moving your hands."*

Notice the progression: layer 1 said "every shortcut without leaving the home row"; layer 2 elaborated the pain and named the transformation; layer 3 introduces tap-vs-hold and is honest about the week of adjustment.

---

## Voice — four pillars

### 1. Value before mechanism

Covered above. This is the single most important rule. New users don't know why they'd want any of our packs until someone names the problem for them. If a description opens with a technical noun (tap-hold, home row, layer, modifier, chord), it's probably failing.

The test: if a reader who has never configured a keyboard can read the opening sentence and think *"yes, I have that problem,"* the copy is doing its job.

### 2. Confident, not salesy

We don't oversell. We don't say "amazing," "powerful," "revolutionary," or "game-changing." We also don't say "just a simple remap" or undersell. The voice is a knowledgeable friend who knows the trade-offs.

**Good:** *"The simplest remap there is: put Escape where Caps Lock used to be."*

**Bad (too salesy):** *"Unlock the full power of your keyboard with revolutionary home-row mods!"*

**Bad (too modest):** *"A small remapping that changes some keys into modifiers when you hold them."*

### 3. Specific, not generic

We name the keys. We name the modifiers. We don't say "various shortcuts" when we mean ⌃⌥⇧⌘. We don't say "some keys" when we mean "a, s, d, f, j, k, l, and ;".

Users can handle precision. Vagueness makes them work harder to figure out what the pack actually does.

**Good:** *"Hold semicolon to turn your left hand into a number and symbol layer."*

**Bad:** *"Activate a convenient symbol layer with a familiar key."*

### 4. Assumes curiosity, not expertise

The reader is smart and interested but hasn't lived in the hobby. Define terms the first time they matter. Don't use jargon for its own sake. Don't write for children either — users can hold one new concept per paragraph.

**Good:** *"Modifier keys — the ones you hold to change what another key does, like ⌘ and ⌃ — normally live in the corners. This pack moves them under your resting fingers."*

**Bad (too hand-holdy):** *"Have you ever wondered what ⌘ does? It's called a modifier! Modifiers are pressed together with other keys!"*

**Bad (too jargony):** *"Activates per-finger tap-hold CAGS-mapped home-row modifiers with chordal hold detection."*

---

## Lexicon

Words we use consistently:

- **Pack** (not rule, not collection, not configuration, not preset)
- **Mapping** (not remap, not rule, not shortcut — for user-facing copy)
- **Hold behavior** (not dual-role, not modifier behavior — explain the concept inline rather than use a term of art)
- **Layer** (keep — the term is unavoidable and users will learn it)
- **Modifier** (keep — standard word, often accompanied by a concrete example on first use)
- **Install** (the verb for adopting a pack — not "add," not "enable")
- **Uninstall** (not "remove," not "disable")
- **The home row** (as a physical location — readers recognize the phrase even if they don't know "home row mods")

Words we avoid:

- "Rule" (deprecated)
- "Configure" (prefer "customize" or just "settings")
- "Feature" (prefer what the thing actually does)
- "Power" / "powerful" (earn it by demonstrating)
- "Advanced" (often means "we couldn't figure out how to make it simple"; avoid unless it genuinely guards complexity beginners shouldn't touch)
- "Smart" (rarely adds meaning)
- "Ultimate" / "best" (never)

### On emoji

Used sparingly, only where a symbol is the clearest way to say the thing. ✓ in a toast for "done" is fine. 🎉 in editorial copy is not. Packs should not have emoji in their names.

### On modifier symbols

Use the Apple symbols: ⌃ ⌥ ⇧ ⌘. Exception: on first mention in a long description, write "⌘ (Command)" to orient readers unfamiliar with the symbols.

---

## Microcopy

### Install toast

*"Home-Row Mods installed · 8 bindings added."*

- Pack name, delimiter ` · `, what happened concretely.
- Include an Undo button labeled just *"Undo."*

### Uninstall toast

*"Home-Row Mods uninstalled."*

No binding count on uninstall — a bare "gone" is enough.

### Override warning (inline, not modal)

*"Overrode Home-Row Mods on this key. [Undo]"*

- Past-tense verb — the action is complete.
- Name the pack.
- Undo in brackets as a link-style action.

### Empty states

- **Gallery → My Packs, none installed:**
  *"No packs installed yet. Browse Discover to find something."*

- **Search, no results:**
  *"No packs match '{query}'. Try a different word, or browse Categories."*

- **Keyboard canvas, no mappings (main window, first run):**
  *"Your keyboard is unmodified. Click any key to remap it, or open the Gallery to browse bundled packs."*

### Errors

Be specific about what went wrong and what the user can do. Never blame the user for something the app should handle.

- **Offline:**
  *"Can't reach the Gallery right now. The Starter Kit is available offline. [Browse Starter Kit]"*

- **Install failed:**
  *"Couldn't install Home-Row Mods: the privileged helper isn't responding. Try reinstalling KeyPath, or restart your Mac."*

- Never: *"An error occurred."* or *"Something went wrong."*

---

## Full example copy — three Starter Kit packs

Pressure-testing the guide with three different packs at three levels of copy.

### 1. Caps Lock → Escape

**Card (layer 1):** *"A useful key where Caps Lock used to be."*

**Short (layer 2):** *"Caps Lock is a key almost no one uses on purpose. Escape is a key you press constantly — and it lives all the way in the corner. This pack makes Caps Lock into Escape, and nothing else."*

**Long (layer 3):**

*"Caps Lock is a vestigial key — a relic of typewriters, sitting in prime real estate on a modern keyboard. Escape, meanwhile, is one of the most-used keys on a Mac: every dialog, every mode, every moment of cancellation wants it. And Apple put it in the top-left corner, where it takes a deliberate stretch to reach.*

*This is the simplest pack in KeyPath — one key, one mapping, no configuration. Install it, press Caps Lock, and nothing happens but an Escape keystroke. It's the remap most users have been told about before they found us; if you've been curious, this is the one to start with."*

### 2. Home-Row Mods — Full CAGS

**Card (layer 1):** *"Every shortcut, without leaving the home row."*

**Short (layer 2):** *"Keyboard shortcuts make you reach for the corners of your keyboard hundreds of times a day. This pack puts Control, Option, Shift, and Command right under your fingertips — every shortcut becomes a single, fluid motion from the home row."*

**Long (layer 3):**

*"Modifier keys — ⌘, ⌥, ⇧, ⌃ — live at the corners of your keyboard, forcing you to reach or curl your fingers to press them. Every time you use a shortcut, your hands move away from the home row. That's thousands of small movements a day that slow you down and, for some people, eventually hurt.*

*This pack assigns a modifier to each of a, s, d, and f, mirrored on j, k, l, and ;. Tap a key normally and you get the letter. Hold it briefly and it acts as a modifier. There's a short learning curve — expect a week of adjusting to the new rhythm — but the payoff is typing every shortcut without ever moving your hands."*

### 3. Smart Quotes & Dashes

**Card (layer 1):** *"Clean punctuation without thinking about it."*

**Short (layer 2):** *"Typing prose on a Mac leaves you with straight quotes where curly ones belong, double-hyphens where em-dashes would read better, and three dots where one ellipsis character would do. This pack fixes all three automatically."*

**Long (layer 3):**

*"Typographers care about punctuation; most writing tools don't. When you type a quote in most apps, you get ″straight quotes″ — the kind a computer likes — instead of the "curly quotes" that look right in published prose. Same with "--" instead of "—", and "..." instead of "…".*

*This pack watches what you type and quietly replaces the wrong character with the right one. Two dashes become an em-dash; three periods become an ellipsis; straight quotes become curly based on where you are in the sentence. It only runs when you're typing into a text field, so it won't interfere with any app that does its own quote handling (like most code editors)."*

---

## Tone calibration — the quick test

A copy draft passes if all four are true:

1. Does the opening sentence name a pain or a goal the user already has?
2. Is a technical term (tap-hold, home row, layer, modifier, chord) used only after the concept has been introduced plainly?
3. Does the copy name specific keys, specific modifiers, specific outcomes (not "various shortcuts" or "some keys")?
4. Would I (the writer) use this copy in conversation, or does it sound like marketing I'd skim?

---

## Ownership

- **Pack descriptions (all three layers)**: written by product/marketing, reviewed by UX lead. The writer should have read the target pack's help doc (if one exists) before drafting.
- **Editorial collection intros**: written by product/marketing, reviewed by UX lead.
- **Microcopy (toasts, errors, empty states)**: owned by UX lead, because these are tightly coupled to UX flows.
- **Category descriptions**: written by product/marketing, reviewed once and stable.

All of it gets reviewed against this guide. When in doubt, err toward the clearer, plainer version.

---

## Related references

- **CLAUDE.md § "Help Content Philosophy"** — the codified content hierarchy. Gallery copy extends this into a new context.
- **`Sources/KeyPathAppKit/Resources/home-row-mods.md`, `tap-hold.md`, `action-uri.md`, `use-cases.md`** — canonical examples of value-first writing already shipping in KeyPath.
- **Starter Kit list** — `docs/design/sprint-1/starter-kit.md` — each pack on that list needs three-layer copy drafted per this guide.

---

**Open item for review:** As we draft copy for the twelve Starter Kit packs, we'll pressure-test this guide and fold learnings back in. The three examples above model the pattern; the remaining nine will be drafted by product/marketing using the same structure.
