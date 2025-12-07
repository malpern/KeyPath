# Kanata → KeyPath Overlay Architecture

> **Note:** This document describes the Live Keyboard Overlay feature, which is available in R2 release only. R1 includes Custom Rules and the Installation Wizard, but not the overlay visualization.

This doc explains how to expose enough runtime state from Kanata to power a feature‑complete KeyPath overlay while keeping changes small, optional, and maintainer‑friendly.

## Goals
- Show both **physical input** and **Kanata outputs** (after layers, tap‑hold, chords, tap‑dance, one‑shots, etc.).
- Keep **keyberon generic**: no Kanata‑specific formatting or stringification in the library.
- Keep **Kanata changes low‑impact**: additive TCP messages, opt‑in, no behavior changes.

## Current State
- TCP `KeyInput` messages provide physical key press/release.
- TCP `LayerChange` / `CurrentLayerName` provide active layer.
- New `HoldActivated` path: keyberon sets a tiny `hold_activated` flag; Kanata reads it and broadcasts `{ key, action:"", t }` (action resolved client‑side).
- No TCP visibility into output keystrokes or other action contexts.

## Design Principles
1. **Minimal signals, read‑once hooks**: keyberon exposes small `take_*` getters that clear internal flags; Kanata decides if/what to broadcast.
2. **Client‑side formatting**: TCP payloads stay structural (coords, key names, step indices). UI resolves labels from its own config map.
3. **Additive, optional protocol**: new messages are opt‑in and backward compatible; older clients keep working.
4. **Feature‑gated**: guard new streams behind a config flag and advertise capabilities over TCP.

## Surface Area Needed for a Complete Overlay
- **Physical input**: keep existing `KeyInput`.
- **Output keystrokes (core need)**: add an **output diff** message produced in Kanata right after `layout.tick()` computes `prev_keys → cur_keys`. Payload: `[{ key, action: "press|release|repeat" }] + timestamp`. No keyberon change.
- **Hold activation**: keep existing `HoldActivated` (coord only).
- **Optional higher‑level hooks** (same pattern as hold; small keyberon additions):
  - `take_tap_dance_step()` → coord + step index fired.
  - `take_chord_triggered()` → coords that formed the chord.
  - `take_oneshot_state()` → which oneshot modifier armed / cleared.
  - Layers already covered by `LayerChange`.

## TCP Protocol Additions (proposed)
- **OutputDiff** (core):  
  `{ "OutputDiff": { "keys": [ { "key": "esc", "action": "press" }, ... ], "t": <ms> } }`
- **TapDanceStep** (optional):  
  `{ "TapDanceStep": { "key": "q", "step": 2, "t": <ms> } }`
- **ChordTriggered** (optional):  
  `{ "ChordTriggered": { "keys": ["a","s"], "t": <ms> } }`
- **OneShotState** (optional):  
  `{ "OneShotState": { "mod": "lctl", "state": "armed|cleared", "t": <ms> } }`
- **FeatureAdvertisement** (handshake):  
  `{ "ServerFeatures": ["output_diff","hold_activated","tap_dance_step", ...] }`

All new messages are additive; consumers ignore unknown fields safely.

## Maintainer‑Friendly Practices
- Keep keyberon changes **tiny and generic**: only add `Option` flags + `take_*` getters; no strings, no Kanata types.
- In Kanata, make broadcasting **conditional** on a config flag (e.g., `tcp_output_diff = yes`).
- Add **tests** in Kanata for:
  - `OutputDiff` correctness on simple press/release.
  - `HoldActivated` still firing when enabled.
  - Each optional hook guarded by its flag.
- Document the TCP schema and the feature list in `tcp_protocol`.
- Default **off** for new streams; enable in KeyPath bundles/config.

## Incremental Plan
1) Implement **OutputDiff** in Kanata (no keyberon change).  
2) Ship with `HoldActivated` (already present).  
3) Add feature advertisement message.  
4) If the overlay needs richer cues, add the optional `take_*` hooks one at a time, each feature‑flagged.  
5) Update KeyPath overlay to:
   - Consume `OutputDiff` for rendered output highlights.
   - Continue resolving labels from `layerKeyMap`.

This path gives the overlay full fidelity (physical + produced outputs) with minimal, opt-in changes and keeps keyberon clean for upstream maintainers.

## Future Work: Simulator positioning for upstream
- Kanata today only ships a web/wasm simulator (jtroo.github.io), not a CLI. Upstreaming a CLI simulator may face scope/maintenance pushback.
- If proposing upstream, keep it as an optional crate/binary (off-by-default) rather than wiring it into the core daemon.
- Alternatively, continue distributing the simulator as a sidecar in KeyPath; it already reuses kanata parser/state logic without touching the core project.
- Build a small TCP integration harness (optional) to assert that HoldActivated is emitted once per tap-hold timeout; gate it behind a feature/env flag so it stays maintainer-friendly.
