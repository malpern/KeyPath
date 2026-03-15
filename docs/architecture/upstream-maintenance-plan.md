# Upstream Maintenance Plan: QMK & Kanata

KeyPath depends on two upstream projects — **QMK** (keyboard firmware ecosystem) and **Kanata** (remapping engine). This document describes each dependency, how it can break, and what maintenance is required.

---

## Kanata (Backend Engine)

### What We Ship

| Component | Source | Version | Build |
|-----------|--------|---------|-------|
| `kanata` binary | Git submodule `External/kanata` (fork: `keypath/bundled` branch) | v1.11.0 | Rust `cargo build --release` with features `cmd,tcp_server` |
| `kanata-sim` | Same submodule | Same | `cargo build --release --package kanata-sim` |
| Host bridge | `Rust/KeyPathKanataHostBridge/` | Local | Rust static/dynamic lib via C ABI |

### Dependencies & Risk

| Dependency | What Could Change | Impact | Frequency |
|------------|-------------------|--------|-----------|
| **TCP protocol** | Message format, field names, new required fields | Runtime communication breaks | Rare — protocol has been stable across v1.9–v1.11 |
| **Config syntax** | `defcfg` options, tap-hold variants, layer-switch semantics | Generated configs rejected by new Kanata | Rare for existing constructs; new features additive |
| **Capability negotiation** | `hello()` response format, capability names | Feature detection fails | Rare |
| **CLI flags** | `--port`, `--cfg`, `--log-layer-changes` | Launch fails | Very rare |
| **Rust toolchain** | MSRV bump, dependency API changes | Build fails | Occasional (follow upstream Rust releases) |

### When to Update Kanata

| Trigger | Action | Effort |
|---------|--------|--------|
| Kanata releases a version with features we want | Update submodule, test build + TCP + config generation | Half day |
| Kanata fixes a bug affecting KeyPath users | Cherry-pick or update submodule | 1–2 hours |
| macOS update breaks Kanata (TCC, IOKit changes) | Coordinate with upstream, may need fork patches | Variable |
| Rust toolchain MSRV bump | Update local Rust toolchain, rebuild | 30 minutes |

### How to Update

```bash
cd External/kanata
git fetch upstream
git merge upstream/main  # or specific tag
cd ../..
./Scripts/build-kanata.sh  # rebuilds with TCC-safe caching
swift test  # verify TCP protocol still works
```

After updating, verify:
1. `kanata --version` shows expected version
2. TCP `hello()` handshake succeeds
3. Config reload works (`Reload` request)
4. HRM stats still report (if capability present)
5. Layer changes broadcast correctly

### Config Syntax We Emit

These are the Kanata constructs KeyPath generates. If upstream changes any of these, the config generator must be updated:

- `defcfg` — `process-unmapped-keys`, `danger-enable-cmd`, `tap-hold-require-prior-idle`
- `defvar` — `$tap-timeout`, `$hold-timeout`, `$chord-timeout`
- `defhands` — `(left ...)`, `(right ...)`
- `defsrc` / `deflayer` — standard key layout blocks
- `defalias` — prefixed aliases (`layer_`, `beh_`, `fork_`, `act_`, `dev_`)
- `tap-hold` variants — `tap-hold`, `tap-hold-press`, `tap-hold-release-keys`, `tap-hold-opposite-hand`
- `tap-dance`, `defchords`, `defseq`, `macro`
- `layer-while-held`, `one-shot-press`
- `switch` with `(device ...)` and app conditions
- `push-msg` for UI signaling

---

## QMK (Keyboard Database & Import)

### What We Depend On

| Dependency | Source | Freshness |
|------------|--------|-----------|
| **Keyboard index** (`qmk-keyboard-index.json`) | Bundled snapshot of ~3,700 keyboard paths | Static — last updated Mar 2026 |
| **Keyboard metadata** (`qmk-keyboard-metadata.json`) | Bundled names/manufacturers | Static — same vintage |
| **Popular keyboards** (`popular-keyboards.json`) | ~18 curated boards with full layout data | Static — manually curated |
| **Keyboard API** (`keyboards.qmk.fm/v1/`) | Live fetch for individual keyboard info.json | Depends on QMK infrastructure |
| **Keymap fetch** (`raw.githubusercontent.com/qmk/`) | Live fetch for keymap.c/keymap.json | Depends on GitHub + QMK repo structure |
| **Keycode mapping** (`QMKKeycodeMapping.swift`) | Hardcoded KC_* → macOS keyCode table | Based on HID spec — rarely changes |
| **Locale aliases** (`QMKKeycodeMapping+LocaleAliases.swift`) | Hardcoded JP_/DE_/FR_/etc. → KC_* table | Based on keyboard standards — rarely changes |

### Dependencies & Risk

| Dependency | What Could Change | Impact | Frequency |
|------------|-------------------|--------|-----------|
| **`keyboards.qmk.fm` API** | Domain, version path, response wrapper format | All live keyboard fetches fail | Very rare (would break entire QMK ecosystem) |
| **`info.json` schema** | Field names, layout array structure | Layout parsing fails for new keyboards | Rare — format stable for years |
| **Keymap.c format** | `LAYOUT_*` macro syntax, new compound functions | Keymap token parsing fails | Rare for existing syntax |
| **Bundled keyboard index** | New keyboards added to QMK | Not searchable until index refreshed | ~50 new keyboards/quarter |
| **KC_* keycode names** | New keycodes added, renames | Unknown keycodes render blank | Very rare for standard keys |
| **Locale aliases** | New locales added to QMK | That locale's keys render blank | ~1–2 new locales/year |
| **GitHub raw URLs** | Branch rename (`master` → `main`), repo restructure | Keymap fetch 404s | Very unlikely |

### Maintenance Tasks

#### Refresh Keyboard Index (Quarterly, Optional)

New QMK keyboards won't appear in search until the index is refreshed. This is low-priority because users can still import by URL.

```bash
# Fetch latest keyboard list from QMK API
curl -s "https://keyboards.qmk.fm/v1/keyboards" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(json.dumps(sorted(data), indent=2))
" > Sources/KeyPathAppKit/Resources/qmk-keyboard-index.json
```

Update search count in UI (`QMKKeyboardSearchView.swift` placeholder text: "Search 3,700+ keyboards...").

#### Add New Locale Aliases (As Reported)

When a user reports blank keys on a keyboard using a new locale (e.g., `keymap_farsi.h`):

1. Fetch the header: `https://raw.githubusercontent.com/qmk/qmk_firmware/master/quantum/keymap_extras/keymap_<locale>.h`
2. Extract base-tier `#define XX_Y KC_Z` mappings
3. Add an `alias("XX", ...)` block to `QMKKeycodeMapping+LocaleAliases.swift`
4. Add a test case to `QMKKeymapParserTests.swift`

Effort: ~15 minutes per locale.

#### Add New Keycodes (Very Rare)

If QMK adds new standard keycodes (extremely rare — HID spec is stable):

1. Add mapping to `QMKKeycodeMapping.swift` (`qmkToMacOS` table)
2. Add label to `QMKKeymapParser.swift` (`keycodeLabel()` function)

#### Update Popular Keyboards Bundle (As Needed)

When a popular keyboard's QMK data changes or a new popular board should be added:

1. Fetch its `info.json` from `keyboards.qmk.fm`
2. Add to `popular-keyboards.json`
3. Optionally add to `qmkToBuiltInLayout` redirect table in `QMKKeyboardDatabase.swift`

#### Update QMK-to-Built-In Redirects (As Needed)

When QMK renames a keyboard path (e.g., `crkbd/rev1` → `crkbd/revision1`):

1. Update `QMKKeyboardDatabase.qmkToBuiltInLayout` dictionary
2. Add both old and new paths to support both

---

## Degradation Behavior

Both dependencies degrade gracefully. Here's what happens if we fall behind:

| Scenario | User Experience | Severity |
|----------|----------------|----------|
| Kanata updated but KeyPath not | KeyPath continues using bundled Kanata version | None — old version still works |
| QMK adds new keyboards | New boards don't appear in search; import by URL still works | Low |
| QMK adds new locale | That locale's keys render blank; quality toast warns user | Low |
| QMK changes API URL | All live keyboard fetches fail; bundled data still works | Medium |
| Kanata changes TCP protocol | Runtime communication fails; config still generates | High |
| Kanata removes a config construct | Generated configs rejected; remapping stops | High |

---

## Monitoring Signals

Things to watch for that indicate maintenance is needed:

- **User reports**: "Keyboard X not found in search" → refresh index
- **User reports**: "Keys are blank on my [locale] keyboard" → add locale aliases
- **CI failure after Kanata update**: TCP tests fail → protocol change
- **macOS beta breaks remapping**: IOKit/TCC changes → coordinate with upstream Kanata
- **QMK API 404s in logs**: API migration → update base URL

---

## Summary

| | Kanata | QMK |
|---|---|---|
| **Update cadence** | When we want new features or bug fixes | Reactive (user reports) |
| **Breaking change risk** | Medium (TCP protocol, config syntax) | Low (stable formats) |
| **Scheduled maintenance** | None required | Optional quarterly index refresh |
| **Effort per update** | Half day (submodule + test) | Minutes (locale aliases, index) |
| **Graceful degradation** | Old version continues working | Bundled data still works offline |
