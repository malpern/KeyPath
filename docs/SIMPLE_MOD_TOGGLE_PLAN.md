## Simple Modifications (A→B) Toggle — Plan

Scope: strictly 1:1 key remaps (e.g., `caps → esc`, `a → b`) on the `base` layer using `deflayermap`. No tap-hold, layers, combos, or per-app scope in MVP.

### Goals
- Toggle common A→B remaps on/off safely and instantly.
- Keep a single source of truth in the managed config; no hidden state drift.
- Be resilient to manual edits and future upgrades.

### Out of scope (MVP)
- Complex rules (tap-hold, chords, home-row mods, app scope).
- Cross-file refactors.

### UX
- Open via File → "Simple key mappings..." (Cmd-K): presents a searchable list of common remaps with a toggle per item.
- Instant apply on flip, with optimistic UI and spinner; revert on error.
- “View in config” jumps to the managed block.

### Config ownership model
- We own a single sentinel-wrapped block that contains a `deflayermap (base)` with one line per mapping.
- Format:
  ```
  # KP:BEGIN simple_mods id=<uuid> version=1
  (deflayermap (base)
    caps esc
    a    b    # KP:DISABLED
    ...
  )
  # KP:END id=<uuid>
  ```
- Enabled line: `from to`.
- Disabled line: add trailing `# KP:DISABLED` marker; we omit these lines when generating the effective config.

### Parser/indexer
- Locate our sentinel block and its `deflayermap (base)`.
- Parse mapping lines into `SimpleMapping` records:
  - `id` (UUID), `fromKey`, `toKey`, `enabled`, `filePath`, `lineRange`.
- Validate keys against known Kanata key names (from canonical set / `defsrc`).
- Detect duplicates within our block (same `fromKey` appearing multiple times) and de-dupe on write (last UI selection wins).

### Writer/toggling
- Toggle on: ensure a single `fromKey toKey` line exists, remove `# KP:DISABLED` if present.
- Toggle off: ensure the line exists and carry a `# KP:DISABLED` marker (or remove from effective config at compile time).
- If sentinel block doesn’t exist, append it at the end of the primary user config with a section header.
- Preserve whitespace/formatting; idempotent writes.

### Instant apply pipeline
1) Debounce/coalesce 150–300 ms to group rapid toggles.
2) Compile effective config in memory from source: copy all content, but exclude lines with `# KP:DISABLED` inside our block.
3) Validate: run Kanata parse/dry-run (or minimal boot) to catch syntax errors.
4) Atomic swap: write to `effective.kbd.tmp`, then rename to `effective.kbd`.
5) Live reload: use `KanataTCPClient` where available; fallback to controlled restart via `LaunchAgentManager`.
6) Health check: `ServiceHealthMonitor` verifies readiness; on failure, rollback to last-known-good `effective.kbd` and revert the toggle UI state.

Concurrency
- Single-flight apply: serialize apply operations; latest state wins.
- Rate-limit reloads (min interval ~500 ms) to avoid thrash.

### Conflicts and loops

App-level detection/handling
- Duplicate within our block: we maintain at most one mapping per `fromKey` (UI enforces uniqueness).
- Duplicate elsewhere in config (outside our block):
  - We detect same `fromKey` set earlier in the resolved order and warn that our mapping may be shadowed or will shadow another.
  - Provide a “Why?” detail showing the conflicting line and file.
- Reciprocal mappings (e.g., `a→b` and `b→a`): allowed; no loop at runtime for simple mappings. We still flag to the user in case it’s accidental.
- Any-key (`_`, `__`, `___`) usage inside our block: we do not emit these in MVP to avoid wide-scope conflicts.

Kanata native behavior (relevant facts)
- Within a single `deflayermap` block, repeating an input key is rejected at parse time:
  - “input key must not be repeated within a layer”.
- Across multiple `deflayermap` blocks or between `deflayer` and `deflayermap`, the last assignment wins (source order precedence). There is no global duplicate error across blocks.
- Simple A→B output is not reinterpreted as new input; no infinite loop from `a→b` and `b→a`.
- Special any-key tokens:
  - `_` maps all keys declared in `defsrc` that are still unmapped.
  - `__` maps keys not listed in `defsrc` (requires `process-unmapped-keys yes`).
  - `___` maps both `defsrc` and unmapped keys (also requires `process-unmapped-keys yes`).
  - Only one of these may be used per layer, and they cannot be mixed together.

What we do with this
- Preflight validation will fail fast on within-block duplicates (we never write them) and on underscore misuse (we don’t generate them in MVP).
- We surface precedence/overshadowing as warnings before apply and in the row detail (“This mapping is superseded by …”).
- We log the final effective mapping for the `fromKey` so users can confirm the active result.

### Validation and rollback
- Validate generated `effective.kbd` before applying.
- On parser error or unhealthy service after reload, rollback and revert UI.
- Keep a rolling backup of last N effective configs.

### Tests
- Parser: sentinel detection, mapping line parse, disabled marker parsing, key validation.
- Writer: create sentinel block, enable/disable mapping, idempotence, dedupe.
- Integration: effective config generation; Kanata parse; reload + rollback when induced error is present.
- UI: optimistic toggle, error reversion, disabled-while-applying state.

### Roadmap
- MVP: global A→B toggles, instant apply, conflict warnings, rollback.
- Next: custom A→B add, import existing lines into managed block, richer catalog.
- Later: per-app scope (moves to complex mods track), templates beyond A→B.



