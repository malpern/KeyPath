# ADR-039: Key Conflict Detection and Resolution Principles

**Status:** Accepted  
**Date:** 2026-05-18  
**Context:** As KeyPath ships more system packs (Vallack, future Miryoku, etc.), collections will increasingly compete for the same well-placed keys — home row, top row, index fingers. The conflict detection and resolution system must handle this gracefully.

## Principles

### 1. Never silently discard a user's intent

When two rules claim the same key, the user must know. Silent deduplication that drops one mapping without notice is a bug, not a feature.

**Corollary:** Auto-resolution is acceptable only when the user explicitly opted in (e.g., `autoResolveConflicts: true` during pack install) or when one claim is purely structural (see Principle 3).

### 2. Detect conflicts at the earliest possible moment

Conflicts should surface **before** the config is generated, not during deduplication. The ideal moment is when the user takes an action that creates the conflict: enabling a collection, installing a pack, or saving a custom rule.

**Detection points, in order of preference:**
1. **Pack install preview** — before the user commits
2. **Collection toggle** — when enabling creates a collision
3. **Rule save** — when a custom rule shadows an existing mapping
4. **Config generation** — last resort; log a warning if reached

### 3. Distinguish structural claims from intentional claims

A collection that puts `f` in `defsrc` because it needs the key on a non-base layer is making a **structural claim** — it doesn't intend to change what `f` does on the base layer. A collection that adds a tap-hold behavior to `f` is making an **intentional claim** — it wants to change the key's behavior.

**Rule:** An intentional claim always takes priority over a structural claim. This resolution is automatic and requires no user input because no user intent is being overridden.

**Implementation:** In config generation deduplication, prefer a non-identity `baseOutput` over an identity passthrough (`baseOutput == sourceKey`). This is the fix applied in this PR for the Vallack system.

### 4. Scope conflicts to the layer they occur on

Two collections can share the same physical key if they operate on different layers. `h → left` on the nav layer and `h → h` on the base layer is not a conflict. `h → left` and `h → home` on the same nav layer is.

### 5. System packs get special conflict handling

A system pack (like Vallack) configures multiple collections as a coordinated unit. When installed, its collections should not silently lose keys to previously-enabled collections. The pack installer should:
1. Detect per-key conflicts with existing enabled collections
2. Show a preview of what will change
3. Offer to disable conflicting collections or skip conflicting keys

### 6. The keyboard shows effective state; the inspector shows provenance

The overlay keyboard always shows what the key **actually does** — the winning mapping after all resolution. It never shows conflict indicators on the keyboard itself. Conflict provenance (which collection owns a key, what was shadowed) belongs in the inspector drawer, the rules tab, and the pack detail view.

### 7. Resolution choices must be reversible

If a user resolves a conflict by disabling Collection A in favor of Collection B, they should be able to re-enable A later. Disabling a collection preserves its configuration — nothing is deleted.

## Current State and Violations

### What works today

| Capability | Implementation |
|-----------|---------------|
| Rule-to-rule conflict detection | `RuleCollectionsManager+ConflictDetection.swift` |
| Interactive conflict dialog | `RuleConflictResolutionDialog.swift` |
| Auto-resolve on pack install | `autoResolveConflicts: true` in mapper/installer |
| Chord group conflict detection | `ChordGroupsConfig.detectCrossGroupConflicts()` |
| Build-time collision tests | `RuleCollectionCollisionTests.swift` |

### Violations of these principles

| Violation | Principle | Location | Severity |
|-----------|-----------|----------|----------|
| Config deduplication silently drops mappings from lower-precedence collections | #1 (never silently discard) | `deduplicateBlocks()` in `KanataConfiguration+BlockBuilders.swift` | High |
| `RuleCollectionDeduplicator.dedupe()` removes duplicate input keys without logging or notifying | #1 | `RuleCollectionDeduplicator.swift:89` | High |
| Pack installer has no per-key conflict detection against existing collections | #2 (detect early) | `PackInstaller.swift` | High |
| No post-install summary showing shadowed keys | #1 | Missing entirely | Medium |
| Mutual exclusivity checks are hardcoded per-pack, not dynamic | #5 (system pack handling) | `PackInstaller.enforcePreInstallGates()` | Medium |
| No cascade analysis (disabling A might affect B) | #2 | Missing entirely | Low |

## Recommendations

1. **Add conflict logging** to both deduplicators so silent drops are at least visible in debug logs
2. **Implement pack conflict preview** (#375) — show what will change before committing
3. **Add post-install summary toast** when keys were auto-resolved during pack install
4. **Replace hardcoded mutual exclusivity** with a dynamic system based on per-key overlap analysis
5. **Add a "shadowed mappings" indicator** to the Rules tab so users can see what's hidden

## Related

- [#375](https://github.com/malpern/KeyPath/issues/375) — Pack conflict detection
- [#379](https://github.com/malpern/KeyPath/issues/379) — Overlay zone coloring (surfaced the dedup bug)
- `docs/design/sprint-2/pack-coherence.md` — Pack coherence design
