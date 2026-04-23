# Rule Collection Test Coverage — Current State and Gaps

## Current coverage

`Tests/KeyPathTests/Config/RuleCollectionKanataValidationTests.swift` runs
`kanata --check` against generated configs for:

1. Every collection in `RuleCollectionCatalog().defaultCollections()`, enabled alone.
2. Three hand-picked risky combos:
   - Home Row Mods + Backup Caps Lock (HRM tap-hold + `defchordsv2`)
   - Caps Lock Remap + Home Row Mods
   - All productivity collections together

Runtime: ~1.5s. Skips cleanly if the bundled kanata binary isn't built.

Pack-side coverage: `PackRegistryTests` (ID uniqueness, alias normalization,
collection back-references) and `PackSummaryProviderTests` (summary string
rendering across tap/hold, single-key, multi-binding paths).

## Gaps worth closing later

### 1. Combo fuzzer
Hand-picked combos catch known-hard interactions but miss unknown ones. At
19 collections, the full pair matrix is 171 combos — cheap enough to run as
a separate, tagged test that fuzzes ~50 random pairs/triples per CI run.
Catches emergent grammar conflicts (e.g. two collections both defining a
layer with the same name, or one collection's aliases colliding with
another's).

### 2. End-to-end install/uninstall flow
`PackInstaller.install → toggleCollection → regenerateConfig → validate →
reload` is currently exercised only by piece. A test that drives the full
chain (with an in-memory store, mocked reload, real validator) would catch
regressions in the wiring — the kind of bug where each unit works but they
pass the wrong thing between layers.

### 3. Runtime behavior (headline-claim tests)
`kanata --check` validates syntax but not semantics. For each pack, assert
the headline claim holds when simulated:

- Caps Lock Remap: pressing caps → escape (tap) / hyper (hold).
- Home Row Mods: `a` tap emits `a`; `a` held emits `lctl`.
- Backup Caps Lock: both shifts → caps.

Kanata ships `kanata-cmd` / simulated-input harness that can drive this.
~1 test per pack, ~100ms each. Catches behavior regressions even when the
config is syntactically valid.

### 4. Pack Detail UI wire-through
The live wire-through from Pack Detail pickers (tap/hold, single-key, HRM)
to `RuleCollectionsManager` config updates has no integration test. Snapshot
test + a headless `@MainActor` test that edits through the picker APIs and
asserts the resulting collection state would cover this.

### 5. Cooldown-aware flows
The 3s TCP reload cooldown has bitten us twice (pack install + tap-hold
edit, and now Backup Caps Lock toggle from Gallery card). A tagged test
that simulates rapid toggles and asserts no chime / no stuck state would
be valuable — plus `SoundManager` should probably no-op in `XCTestCase`
to stop tests from producing audible beeps.

## Priority

If we do one of these, **#3 (runtime behavior)** gives the most lift —
it's the only thing that catches "config is valid but doesn't actually do
what the pack promises." Everything else catches breakage in layers that
already have some coverage.
