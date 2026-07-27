---
layout: default
title: "Why Text Tools Break in Electron Apps"
description: "Research note on the accessibility gaps that stop vim modes and text automation from working in Slack, Discord, and VS Code — and who can fix each one"
theme: parchment
permalink: /guides/electron-text-parity/
---


# Why Text Tools Break in Electron Apps

If you use [KindaVim]({{ '/guides/kindavim/' | relative_url }}), a text expander, or any other
keyboard-driven text tool, you have probably noticed the same thing: it works beautifully in Mail,
Notes, and Xcode, then falls apart in Slack.

This is a research note explaining why. It is written for people who want to fix the problem
upstream, not for people configuring KeyPath — if you just want KindaVim working today, the
[KindaVim guide]({{ '/guides/kindavim/' | relative_url }}) covers the practical workarounds.

**Short version:** the failure is mostly Chromium's, not Apple's, and most of it is ordinary
bug-fixing rather than missing API.

---

## Five Things Have to Work

Parity with a native macOS text field is not one capability, it is a chain:

| # | Capability | Native field | Electron field |
|---|------------|--------------|----------------|
| 1 | Accessibility tree exists | Works | Manual, per app |
| 2 | Tree is trustworthy | Works | Falsely claims support |
| 3 | Reads are correct | Works | Offsets wrong |
| 4 | Writes propagate to the app | Works | Model desync |
| 5 | Changes are observable | Works | Timing unreliable |

Stage 2 is the load-bearing failure. Because Electron answers "yes, I support accessibility" and
then returns wrong data, no tool can auto-detect its way out — which is why every assistive tool
surveyed ships a hand-curated per-app blocklist instead.

---

## The Gap Register

Item IDs are stable and intended to be quotable in upstream bug reports.

### Chromium — 6 gaps, the bulk of the work

Almost everything that makes Electron text fields unusable lives here, and almost all of it is
ordinary bug-fixing. No Apple dependency.

**C1 — Text offset mapping is wrong.** A line starting with whitespace reports a character range
off by one. Selecting exactly to end-of-line silently swallows the following line break. This is
Blink's mapping between DOM positions and flat macOS character indices. The reporter shipped a
reproducible Swift test case noting native apps don't behave this way.

For a navigation tool this misplaces the cursor. For a tool that *replaces* a range, it eats the
user's characters — same bug, an order of magnitude more damage. **This is the highest-value fix.**

**C2 — Rich `contenteditable` has no coherent linearization.** Slack's composer, Notion, and
Discord are DOM trees, not strings. Mentions, emoji, and code blocks become opaque nodes. There is
no stable contract for how a rich editor projects onto a flat `AXValue` plus character offsets, so
the offsets don't correspond to what the user sees. WebKit handles this better, so it's tractable,
but this is design work rather than a bug fix — the hardest item on the board.

**C3 — Write-path fidelity.** Setting `AXValue` or `AXSelectedTextRange` needs to route through
Blink's editing pipeline so `beforeinput` and `input` fire and the page's JavaScript observes the
change. If it mutates the DOM without that, editors built on React, Lexical, or ProseMirror
desync: the visible text changes, the app's model doesn't, the message sends stale, and undo
breaks.

*Unverified — this is reasoning from observed symptoms, not from reading Blink. Check the source
before filing.*

**C4 — No granular `AXMode` for runtime clients.** The `form-controls` bundle already exists, but
only as the `--force-renderer-accessibility` startup flag. A client enabling accessibility at
runtime gets all-or-nothing `complete`. A text tool wants exactly `form-controls` — cheap enough
that the "off by default for performance" objection evaporates. This is what makes always-on
politically possible rather than merely technically possible.

**C5 — No tree-readiness signal.** Activation is asynchronous. Enable accessibility, query
immediately, get an empty or partial tree. There's no documented "ready" notification, so every
tool polls or guesses.

**C6 — No conformance tests for the Mac text APIs.** Without round-trip range tests, C1 regresses
forever. The boring item that decides whether the others stay fixed.

### Electron — 4 gaps, small surface, decisive impact

**E1 — Stop advertising accessibility support until the tree is real.** The cheapest
high-leverage change available. It is the reason every assistive tool ships a curated blocklist.
Fix it and auto-detection starts working everywhere, for every tool, immediately — no Apple
involvement, no performance trade-off, small diff.

**E2 — `AXManualAccessibility` robustness.** The attribute was silently unsettable for roughly two
years: handled internally but never advertised via `accessibilityAttributeNames`, so setting it
returned `kAXErrorAttributeUnsupported`. Fixed in 2023 by an outside contributor. Still needs a
regression test.

**E3 — Expose the granular mode.** `app.setAccessibilitySupportEnabled` is a boolean. Once C4
exists it should take a level.

**E4 — Own the text layer.** The offset bug was closed as not planned with no determination of
whether it was an Electron or a Chromium defect. That triage vacuum — not the difficulty of the
fix — is why these sit for years.

### Apple — 4 gaps, genuinely nobody else can

These aren't bugs, they're missing contracts.

**A1 — There is no documented text-position API.** `AXTextMarker` and `AXTextMarkerRange` are
private, undocumented functions in the HIServices framework. Browsers implement them for VoiceOver
precisely because the public character-index APIs are insufficient for web content. The working
path is undocumented and the documented path is the broken one. This sets the ceiling on how well
any third-party tool can ever handle rich editors.

**A2 — No first-class assistive-technology activation.** `AXEnhancedUserInterface` means "VoiceOver
is running," not "a tool needs data," and it carries side effects — Vimac removed it after it
caused window-positioning problems with window managers like Magnet. `AXManualAccessibility` is
Electron's private invention that other frameworks don't honor.

**A3 — Custom attributes have no modern equivalent.** `accessibilityAttributeNames` and
`accessibilitySetValue:forAttribute:` belong to the deprecated informal protocol, with no
`NSAccessibility` replacement. A2's workaround is built on API Apple deprecated without a
successor — which is exactly what made E2's two-year bug possible.

**A4 — No capability negotiation.** Nothing lets an app declare "my text ranges are correct." That's
why E1 can only ever be a convention Electron chooses to honor, not a contract the system enforces.

---

## Four Tools Hit This Independently

None of them fixed it. They all routed around it — and that convergence is the strongest evidence
for where the gaps actually are.

| Tool | What they found | Route around |
|------|-----------------|--------------|
| KindaVim | Slack returns line numbers where caret offsets belong; Firefox reports accessibility enabled when it isn't | Two strategies + curated plist |
| Vimac | `AXEnhancedUserInterface` broke third-party window managers; filed with Apple, Chromium, and Firefox | Manual attribute, frontmost only |
| Espanso | Keystroke injection fails in VS Code, Slack, and Discord | `force_mode: clipboard` |
| Shortcat | "Effectiveness varies depending on the application's accessibility implementation" | Documented caveat |

Every project reached the same three conclusions without coordinating: force-enable the tree, don't
trust the reads, and mutate through the clipboard or synthesized keys rather than through
accessibility writes.

The contrast with the one serious attempt to fix it upstream is the real finding. Electron
[#36337 ↗](https://github.com/electron/electron/issues/36337) reported the offset bug with a
reproducible Swift test case and was closed as not planned. Working around the gap succeeds;
fixing it does not get traction.

---

## Shortest Path to Parity

**C1 + C3 + E1** gets you correct reads, writes that stick, and honest detection — roughly 90% of
the gap, with zero Apple dependency.

**C4** turns that from a per-app opt-in into something shippable on by default. **A1** is the
ceiling on rich `contenteditable`; everything else on Apple's side is ergonomics.

The practical read for today, while none of this is fixed: Espanso's finding points squarely at
paste-based mutation. It routes around C3 entirely, because the app handles paste through its own
native path — so the JavaScript model updates correctly without anyone touching Blink.

---

## Confidence

- **Cited** — C1, C4, C5, E1–E4, and A1–A3 each rest on a primary source listed below.
- **Inference** — Four items are reasoning rather than citation, and should be verified before
  anyone quotes them upstream. **C3** (write-path fidelity) argues from observed symptoms rather
  than from reading Blink. **C2**'s claim that WebKit linearizes rich editors better is domain
  judgement, not a measured comparison. **C6** (absence of conformance tests) is inferred from C1
  persisting, not confirmed against Chromium's test suite. **A4** (no capability negotiation) is an
  observation that no such API exists — easy to falsify if one does.
- **Stale** — Most recent activity found is 2023–24. Nothing surfaced for 2025–26 on the
  text-range side, but that's absence of search results, not proof of inactivity. Check the
  Chromium tracker before filing against C1.

---

## Sources

- [electron#36337 ↗](https://github.com/electron/electron/issues/36337) — offset bug, closed not planned
- [electron#37465 ↗](https://github.com/electron/electron/issues/37465) — attribute unsettable
- [electron#10305 ↗](https://github.com/electron/electron/pull/10305) — `AXManualAccessibility` added
- [vimac#78 ↗](https://github.com/nchudleigh/vimac/issues/78) — activation side effects
- [kindaVim#70 ↗](https://github.com/godbout/kindaVim.docs/issues/70) — Firefox false positive
- [kindaVim: reaching inputs ↗](https://github.com/godbout/kindaVim.blahblah/discussions/43) — author's diagnosis
- [Espanso backends ↗](https://espanso.org/docs/matches/basics/) — inject vs clipboard
- [Chromium accessibility overview ↗](https://chromium.googlesource.com/chromium/src/+/lkgr/docs/accessibility/overview.md) — AXMode bundles
- [Chromium Mac accessibility ↗](https://www.chromium.org/developers/accessibility/mac-accessibility/) — activation model
- [hs.axuielement.axtextmarker ↗](https://www.hammerspoon.org/docs/hs.axuielement.axtextmarker.html) — private HIServices API
- [Chromium accessibility performance ↗](https://developer.chrome.com/blog/chromium-accessibility-performance) — the default-off rationale
- [Shortcat ↗](https://shortcat.app/) — compatibility caveat

---

## Where to Go Next

- **[KindaVim]({{ '/guides/kindavim/' | relative_url }})** — Real vim modes system-wide, and the practical workarounds for apps like Slack
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**
