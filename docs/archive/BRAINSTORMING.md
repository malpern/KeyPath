## KeyPath Feature Brainstorming

### High-level take
Overall, these are strong directions that lean into KeyPath’s strengths around Kanata and power-user workflows. The biggest wins are features that make powerful configs discoverable, visible, and easy to toggle without sacrificing control.

### Comparison (value, uniqueness, effort, suggested priority)
| Idea | Value | Uniqueness vs others | Effort | Priority |
|---|---|---|---|---|
| 1) Simple modifications toggle | High (broad use, instant gratification) | Moderate (Karabiner has it; doing it reliably in Kanata is novel) | Low–Medium | 1 |
| 4) Keymap visualizer overlay | High (constant visible utility; great onboarding) | Moderate–High (few good overlays; strong for home row mods) | Medium | 2 |
| 2) Complex rules visualizer/manager | High for power users; long-term moat | High (few tools make complex Kanata rules approachable) | High | 3 |
| 3) LLM “describe a mapping” to rule | Medium–High (wow factor, speeds creation) | Medium (others dabble, but integrated Kanata management is unique) | Medium–High | 4 |
| 0) 4D render keys replacing text boxes | Low–Medium (polish, fun) | High (novel UI) | Medium–High | 5 |

### Why this prioritization
- Bold, easy win first: Simple modifications toggles give immediate utility and establish reliable config editing foundations.
- Make power visible early: The overlay helps users understand layers, home-row mods, and current state without reading configs.
- Build the moat: Complex-rule visualization/management is hard but differentiating; do it incrementally after groundwork.
- Add acceleration: LLM creation becomes much more valuable once the system can visualize, tag, toggle, and validate.
- Keep the 4D keys as polish: Save for later or fold a minimal animation into the visualizer once the basics ship.

### Implementation notes for the top 2–3
- 1) Simple modifications toggle
  - Use stable markers in Kanata configs to “own” rule blocks:
    - Example: comment sentinels with a UUID and type metadata:
      - `# KP:BEGIN simple_mod id=abc123 source=generic`
      - rule lines …
      - `# KP:END id=abc123`
  - Maintain an index mapping IDs to file offsets; allow on/off via comment-out or `if` guards.
  - Start with a curated set: caps to esc/ctrl, home-row mods, vim arrows, cmd-h/j/k/l, app-launchers.
  - Add per-app support by emitting wrapped app-condition blocks when relevant.

- 4) Keymap visualizer overlay
  - Always-on-top, resizable, movable overlay; fade inactive layers to 10% opacity.
  - Show current active layers, home-row mods state, and conditional bindings for the frontmost app.
  - Data source: parse current compiled config + runtime state; subscribe to frontmost app changes to update.
  - MVP: read-only view; next: click-to-jump to rule in editor; later: inline toggles for known blocks.

- 2) Complex rules visualizer/manager
  - Phase 1 (read-only): Graph of layers, combos, holds, tap-holds; highlight conflicted or shadowed rules.
  - Phase 2 (scoped editing): Edit parameters for marked blocks (via the same sentinel system as above).
  - Phase 3 (creation): Guided wizards for common complex patterns (tap-hold, multi-layer chords).

- 3) LLM rule generator
  - Bound the output to a known subset (simple mods + a few complex templates).
  - Post-process with a validator and show a diff preview; insert wrapped with sentinels.
  - Add app-aware prompts (“for Xcode only”, “global”, “when Vim layer active”).

### Three additional ideas worth doing
- **Per-app profiles with auto-switching**: Detect frontmost app and toggle relevant layers/blocks. High value, Medium effort, great synergy with overlay.
- **Preset gallery and sync**: Built-in templates (home-row mods variants, Vim arrows, macOS productivity kits), one-click import/export via Gist or iCloud Drive. Medium value, Low–Medium effort.
- **Conflict detector and health panel**: Scan for shadowed mappings, unreachable chords, duplicate binds, and permissions/service issues; one-click fixes. High trust builder, Medium effort.

### Rough effort (single dev, focused)
- Simple modifications toggle: 1–2 weeks to robust MVP with markers, toggles, and UI.
- Keymap visualizer overlay (read-only): 2–3 weeks MVP; +1–2 weeks to polish interactions.
- Complex rules visualizer (read-only): 2–4 weeks MVP; editing flows add 3–6 weeks incrementally.
- LLM mapping: 1–2 weeks MVP bounded scope; +1–2 weeks for validation, diff, undo.
- 4D keys UI: 2–4+ weeks depending on fidelity.

### Suggested phased roadmap
- Phase A (weeks 1–3): Simple mods toggles + config sentinels + basic preset pack.
- Phase B (weeks 3–6): Keymap overlay (read-only), per-app auto-switching, conflict detector basics.
- Phase C (weeks 6–10): Complex rules visualizer (read-only), click-to-locate in config, more presets.
- Phase D (weeks 10–12): LLM bounded generator with validate/preview/insert.
- Phase E: Add inline editing to visualizer; optional fun 4D animations.

### Summary
- Prioritize: 1) Simple toggles → 4) Visualizer → 2) Complex manager → 3) LLM → 0) 4D keys.
- Use sentinel-wrapped, UUID-tagged blocks to safely own and toggle config sections.
- Early overlay + per-app switching materially improve daily value and onboarding.
- Add preset gallery and conflict detector for adoption and trust.

