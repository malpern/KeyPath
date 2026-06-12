# WWDC 2026 / macOS 27: Opportunities for KeyPath

*Research date: June 12, 2026 (WWDC26 week). Developer betas of macOS 27 are out;
public release expected September 2026.*

This doc maps the WWDC 2026 announcements against the current KeyPath codebase and
ranks the resulting opportunities by reward vs. effort. **All of this is post-1.0
work** — nothing here blocks the 1.0 launch. GitHub issues for the major items are
tagged `wwdc26` + `post-1.0`.

## What Apple announced (the parts that touch KeyPath)

- **Foundation Models framework, v2** — a public `LanguageModel` protocol so one
  Swift API drives Apple's on-device model, cloud models (including **Claude** and
  Gemini), or any custom provider; providers swap without code changes. Also:
  multimodal (image) prompts, Dynamic Profiles for swapping models/tools/instructions
  at runtime, a free Private Cloud Compute tier (Small Business Program / under 2M
  first-time App Store downloads), an **Evaluations framework** for validating AI
  features beyond unit tests, and an `fm` CLI + Python SDK.
- **Siri AI** — the rebuilt Siri shipped; on the Mac it lives in Spotlight. App
  Intents gains **Entity Schemas** (feeding Spotlight's semantic index), **Intent
  Schemas** for natural-language actions, View Annotations, and an **App Intents
  Testing Framework** that exercises intents through system pathways without UI
  automation.
- **SwiftUI** — reorderable-container APIs (drag-reorder in any container, not just
  `List`), lazy stacks with prefetch, lazy `@State` class initialization, significant
  ViewBuilder build-time improvements in Xcode 27, new Document API.
- **AppKit** — refreshed materials/typography, corner-concentricity APIs, and
  **automatic `@Observable` tracking in `draw`/`layout`/`updateConstraints`**, which
  is **back-deployable to macOS 15** and on by default with the 2026 releases.
- **Testing & tooling** — Swift Testing ↔ XCTest interoperability for incremental
  migration; Xcode 27 with integrated coding agents, Device Hub, customizable
  toolbar; Swift 6.4 (simplified availability syntax, `@diagnose`); Foundation URL
  parsing up to 4× faster.
- **SwiftData** — gap-filling only; nothing transformative.

## Where KeyPath stands (June 2026)

- Swift 6.1, strict concurrency (`.v6`) on all targets; macOS 15 minimum.
- Liquid Glass already availability-gated for macOS 26
  (`Sources/KeyPathLayoutTracerKit/LiquidGlassSupport.swift`).
- Hybrid AppKit + SwiftUI (`MainWindowController`, overlay windows).
- Direct Anthropic API integration for config repair
  (`Sources/KeyPathAppKit/Services/AI/AnthropicConfigRepairService.swift`, Keychain
  key, biometric gate, `AICostTracker`). No FoundationModels usage anywhere.
- App Intents shipping today (`Sources/KeyPathAppKit/Intents/KeyPathShortcuts.swift`:
  `GetCurrentLayerIntent`, `ServiceControlIntent`, `SendActionIntent`).
- Tests: ~294 XCTest files vs ~48 Swift Testing files.
- Persistence: Kanata `.kbd` file + JSON stores + UserDefaults (no SwiftData).
- SMAppService/XPC privileged helper; Sparkle distribution outside the App Store.

## Ranked opportunities

| # | Opportunity | Reward | Effort | Verdict |
|---|------------|--------|--------|---------|
| 1 | Foundation Models behind the AI config-repair service | Very high | Medium | Do it |
| 2 | App Intents Entity/Intent Schemas → Siri AI & Spotlight | High | Low–Med | Do it |
| 3 | App Intents Testing Framework | Medium | Low | Easy win |
| 4 | AppKit auto-observation (back-deploys to macOS 15) | Medium | Low | Easy win |
| 5 | Xcode 27 + Swift 6.4 toolchain upgrade | Medium | Very low | Free |
| 6 | Evaluations framework for the AI repair feature | Medium | Medium | Worthwhile |
| 7 | Swift Testing migration via XCTest interop | Medium | High (amortizable) | Policy change, not a project |
| 8 | SwiftUI reorderable containers + perf APIs | Low–Med | Low | Opportunistic |
| 9 | macOS 27 design refresh pass | Low | Low | When on the 27 SDK |
| 10 | SwiftData / Core AI / Document API | ~None | — | Skip |

### 1. Foundation Models for AI config repair

The biggest UX barrier to the AI repair feature today is "bring your own Anthropic
API key" (hence the Keychain plumbing, key validator, biometric gate, and cost
tracker). Foundation Models v2 changes the calculus three ways:

- The on-device model can likely handle simple Kanata syntax repairs **free,
  offline, with zero key setup**.
- The `LanguageModel` protocol keeps **Claude as the escalation path through the
  same API**.
- The free Private Cloud Compute tier may eliminate user-borne cost entirely.
  Eligibility is tied to the Small Business Program — needs verification for a
  non-App-Store Developer ID app.

**Shape:** extract a `ConfigRepairModel` protocol now; make
`AnthropicConfigRepairService` one implementation; add a FoundationModels-backed
implementation gated `if #available(macOS 27, *)` (same pattern as
`LiquidGlassSupport`). Tiered routing (on-device first, cloud for hard cases) falls
out naturally. The URLSession path remains the macOS 15–26 fallback.

### 2. Entity Schemas / Siri AI integration for existing App Intents

Siri AI on the Mac lives in Spotlight, and Entity Schemas feed Spotlight's semantic
index. KeyPath already ships three intents; the marginal cost of exposing **rules,
packs, and layers as schema-conforming entities** is small. Payoff: "switch to my
vim layer" / "is KeyPath running?" works from Siri and Spotlight by name —
differentiation no other keyboard remapper will have on macOS 27 day one.

### 3. App Intents Testing Framework

Current UI QA leans on Computer Use, which is slow and flaky by nature. The new
framework validates intents through real system pathways with no UI automation —
cheap, deterministic coverage for exactly the surface item 2 expands. Pairs with #2.

### 4. AppKit automatic observation tracking

Back-deploys to **macOS 15**, so it's adoptable without waiting on a
deployment-target bump. `MainWindowController` and the overlay windows can read
`@Observable` view-model properties directly in `draw`/`layout` and get automatic
invalidation, removing manual sync plumbing between the SwiftUI and AppKit halves.
First step: audit the AppKit layer for hand-rolled notification/KVO bridges.

### 5. Toolchain freebies

Xcode 27 buys ViewBuilder build-time improvements (real money on ~350 test files +
23 targets), 4× faster Foundation URL parsing, and Swift 6.4's `@diagnose` and
simplified availability syntax. Strict-concurrency work is already done, so 6.4
should be a quiet upgrade. Validate CI + `mise.toml`/pinned-tool interactions.

### 6. Evaluations framework for the AI repair feature

KeyPath has an LLM feature with no systematic quality measurement. A corpus of
broken `.kbd` configs with expected repairs, run through the Evaluations framework,
becomes a regression gate — and is a prerequisite for confidently routing "easy"
repairs to the on-device model in #1.

### 7. Swift Testing migration — change the policy, not the codebase

XCTest interop removes the main blocker (shared helpers like `KeyPathTestCase` and
its pgrep-deadlock guard couldn't straddle frameworks safely). Don't run a 294-file
migration project. Instead: new tests use Swift Testing; port the `KeyPathTestCase`
safety guards to a Swift Testing trait/fixture; convert files opportunistically when
touched. Parameterized `@Test` cases fit the layout/keymap matrices well.

### 8–9. SwiftUI and design polish

The reorderable-container API is a direct fit for rule/pack list reordering;
lazy-stack prefetching could help gallery views. The macOS 27 materials/concentricity
refresh is a small additive pass on top of the existing `LiquidGlassSupport` gating
pattern.

### 10. Explicit non-recommendations

- **SwiftData** — persistence is the Kanata `.kbd` file (external source of truth)
  plus small JSON stores; SwiftData adds a sync/migration layer KeyPath doesn't
  need, and even Apple's community reads this year's update as gap-filling.
- **Core AI** — for custom on-device model inference; KeyPath has none.
- **Document API** — KeyPath isn't document-based.
- Nothing announced affects SMAppService, XPC, or the TCC/Input Monitoring surface.
  The daemon/helper architecture and `PermissionOracle` need no changes — but
  **regression-test permissions on the macOS 27 betas**, since TCC behavior shifts
  are historically where major releases bite this app.

## Sequencing (all post-1.0)

1. **Now (macOS 15+ safe):** #4 AppKit observation, #5 toolchain, #7 testing policy,
   and the `ConfigRepairModel` protocol refactor that stages #1.
2. **Against the betas this summer:** #1 FoundationModels implementation, #2 Entity
   Schemas, #3 intent tests, #6 evals — targeting macOS 27 GM in September.
3. **At GM:** #8/#9 polish; start the clock on eventually raising the deployment
   target so availability gates can retire.

## Sources

- [Apple — What's New in macOS](https://developer.apple.com/macos/whats-new/)
- [MacRumors — Platforms State of the Union](https://www.macrumors.com/2026/06/09/apple-outlines-major-ai-and-developer-tool-updates/)
- [TechCrunch — WWDC 2026 everything announced](https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/)
- [Engadget — WWDC 2026 keynote recap](https://www.engadget.com/2189698/everything-announced-at-apples-wwdc-2026-keynote/)
- [Fatbobman's Swift Weekly #139](https://fatbobman.com/en/weekly/issue-139/)
- [Appcircle — What's New in Xcode 27](https://appcircle.io/blog/wwdc26-whats-new-in-xcode-27-for-developers)
- [Apple — Migrate to Swift Testing (WWDC26 session)](https://developer.apple.com/videos/play/wwdc2026/267/)
- [TechTimes — Foundation Models provider swapping](https://www.techtimes.com/articles/318039/20260609/wwdc-2026-developer-tools-foundation-models-now-swaps-ai-providers-without-code-changes.htm)
