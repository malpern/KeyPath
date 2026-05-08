---
layout: default
title: "Next Steps: Context Provider & Action Handler Evolution"
description: Evolving KeyPath toward the context provider / action handler pattern inspired by KE 16 and kanata's TCP architecture
---

# Next Steps: Context Provider & Action Handler Evolution

## Background

Karabiner-Elements 16 (May 2026) added Accessibility API integration for context-aware remapping — detecting overlay windows, focused UI elements, and element properties (role, subrole, title, geometry). They built this into the KE core.

Kanata's philosophy (per jtroo in #40, #1304) is that this kind of platform-specific context belongs outside the remapper, mediated by the TCP server. KeyPath is well-positioned to fill that role on macOS.

KeyPath already implements:
- **Action handler** (95% complete): receives `push-msg` events, dispatches to 9 native macOS action types via ActionDispatcher
- **Context provider** (20% complete): detects frontmost app via NSWorkspace, pushes state into kanata via virtual keys (ActOnFakeKey)

This document outlines what to build next.

## 1. Move from Virtual Keys to defvar for Context

**Why:** Virtual keys are binary (pressed/released) and work for app identity, but can't carry rich context like "focused element is a text field" or "window title contains Draft." Variables (`defvar`) support arbitrary string values and are more natural for the `switch` conditions we want to generate.

**What to investigate:**
- Does kanata's TCP protocol currently support setting `defvar` values from a client? Check the wire protocol and source.
- If not, could we propose it? This would be a small, well-scoped addition to the TCP protocol — a `SetVar` message that sets a runtime variable. jtroo's `custom-behaviour` issue (#797) and the existing `push-msg` implementation (#854) suggest he's open to this kind of extension.
- Fallback: we could use fake keys mapped to `(on-press (defvar name value))` as an indirect mechanism, but native TCP support would be cleaner.

**Config generation impact:** AppConfigGenerator would shift from generating `(input virtual vk_safari)` switch conditions to `(var frontmost-app "com.apple.Safari")` conditions. More readable and more flexible.

## 2. Accessibility API Integration

**Why:** This is the gap between what KeyPath provides today and what KE 16 offers. NSWorkspace tells us which app is frontmost. The Accessibility API (AXUIElement) tells us what's happening *inside* that app.

**What to build:**
- AXObserver watching for focused element changes (`kAXFocusedUIElementChangedNotification`)
- Extract element properties: role, subrole, title, value (for text fields)
- Detect overlay windows (Spotlight, Alfred, command palettes) — the specific thing KE 16 added
- Push this state into kanata as variables: `focused-element-role`, `is-text-field`, `overlay-active`

**Permissions:** Requires Accessibility permission (already needed for some KeyPath features). Should be gated behind user opt-in since it's a significant permission.

**Privacy considerations:** Element properties like title and value can contain sensitive content. KeyPath should:
- Only extract role/subrole by default (structural, not content)
- Make title/value extraction opt-in per app
- Never log or persist element values

**Performance:** AXUIElement queries are synchronous and can be slow for complex UIs. Use a dedicated background thread, debounce rapid focus changes (50-100ms), and skip extraction for apps the user hasn't configured rules for.

## 3. Tool-Specific Context (Layers 3 & 4 from context-integration-architecture.md)

The existing context-integration-architecture.md describes shell integration (Layer 3) and explicit tool notifications (Layer 4). These remain relevant:

- **Shell context** (cwd, git branch, last command) via zsh/bash precmd hooks
- **Tmux context** (session, window, pane, mode) via tmux hooks or status polling
- **Vim/Neovim context** (mode, filetype, buffer) via autocmd → TCP

The ContextUpdate message type proposed in that doc is the right shape. The question is whether this context flows through KeyPath (which aggregates and forwards to kanata) or directly to kanata's TCP server. If KeyPath is the aggregator, it can provide a unified context store with TTL, conflict resolution, and UI for inspecting current state. If tools talk to kanata directly, KeyPath is just one context provider among many.

**Recommendation:** Start with KeyPath as aggregator — it simplifies the kanata config (one source of variables) and gives us a place to build debugging/inspection UI. Can always decentralize later.

## 4. Config Generation for Context-Aware Rules

**Current:** AppConfigGenerator produces `defvirtualkeys` + `switch` rules with `(input virtual ...)` conditions.

**Next:** Generate configs that use `defvar` + `switch` with variable conditions:

```lisp
(defvar
  frontmost-app "unknown"
  focused-role "unknown"
  is-text-field "false"
  overlay-active "false"
  tmux-mode "shell"
)

(defalias
  ;; Only remap in Safari when NOT in a text field
  kp-j (switch
    ((and (var frontmost-app "com.apple.Safari") (var is-text-field "false"))) down
    () j
  )

  ;; Context-aware escape: close overlay if active, otherwise normal esc
  kp-esc (switch
    ((var overlay-active "true")) (multi (defvar overlay-active "false") esc)
    () esc
  )
)
```

This is where the context provider and config generation intersect — KeyPath generates configs that expect live variables, and KeyPath's runtime feeds those variables.

## 5. Prioritized Roadmap

| Priority | Item | Effort | Dependency |
|----------|------|--------|------------|
| 1 | Investigate defvar-over-TCP support in kanata | S | None |
| 2 | AXObserver for focused element role/subrole | M | Accessibility permission |
| 3 | Overlay window detection | M | #2 |
| 4 | Config generation with defvar conditions | M | #1 |
| 5 | Shell context via precmd hooks | S | #1 |
| 6 | Context debugging UI (show current variables) | M | #1-3 |
| 7 | Tmux/vim context providers | M | #1 |

## 6. Open Questions

- **Does kanata's TCP protocol support SetVar today?** If not, is this something we should propose as a PR or discuss in an issue first? Given jtroo's preference for quality contributions (#1839 feedback), an issue with a clear use case would be the right starting point.
- **Should context providers set kanata variables directly, or should KeyPath mediate?** Direct is simpler; mediated gives us aggregation, TTL, and debugging UI.
- **How do we handle context variable naming conventions?** If multiple tools start pushing variables, we need namespacing (e.g., `kp.frontmost-app`, `kp.focused-role`) to avoid collisions with user-defined variables.
- **What's the performance ceiling?** Every context change triggers a variable update over TCP, which kanata processes. Need to verify this doesn't add latency to keypress handling, especially with rapid context changes (fast app switching, mouse movement across elements).
