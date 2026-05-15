# KeyPath Kanata Fork Reduction Plan

The KeyPath kanata fork (`External/kanata`, branch `keypath/bundled`) carries
local commits on top of upstream `jtroo/kanata`. Each commit increases rebase
burden when upstream moves. This document tracks which fork features can be
upstreamed or dropped, and which must stay local.

See also `External/kanata/docs/keypath-fork-status.md` for the branch model
and full inventory.

## Current fork commits (as of 2026-05-15)

15 commits on `keypath/bundled` on top of `upstream/main`.

### Fork-only (maintain permanently)

These are KeyPath app features with no upstream value.

| Commit | Feature | Purpose |
|--------|---------|---------|
| `ba7bb0c` | KeyInput TCP broadcast | Live overlay needs per-key input events over TCP |
| `826e4c3` | TapHoldReason tracing | HRM decision inspector in overlay UI |
| `1556eb4` | --json + canonical_key_name | KeyPath simulator test suite needs structured JSON output |

### Open upstream PRs

When merged, drop from `keypath/bundled` and pick up via upstream sync.

| Commit(s) | Feature | PR | Status |
|-----------|---------|-----|--------|
| `8ca9dac`, `127e76f`, `e722a96`, `870394f`, `9c8dc71` | managed-repeat + companion fixes | [#2070](https://github.com/jtroo/kanata/pull/2070) | Open, 2 comments |
| `23257d3`, `b8e9175` | macos-continue-if-no-devs-found + listener fix | [#2065](https://github.com/jtroo/kanata/pull/2065) | Open, no activity |

### Ready to file

Small changes that should be submitted as upstream PRs.

| Commit | Feature | Size |
|--------|---------|------|
| `4f707a1` | VirtualHID wait timeout 10s → 120s | 2-line fix |
| `9af12d9` | VID:PID hex column in `--list` output | 1 file |

### Auto-drop on next sync

| Commit | Feature | Reason |
|--------|---------|--------|
| `98ccffd` | Config docs for continue-if-no-devs | Ships with PR #2065 |
| `0755b6a` | Design notes for continue-if-no-devs | Internal reference only |
| `c603875` | Fork status doc | Lives in the fork only |

## Dropped features

### `macos-dev-ids-include` (dropped 2026-05-15)

Upstream's `definputdevices` (PR #1989, merged) supports `vendor_id`
and `product_id` matching on macOS. This makes `macos-dev-ids-include`
redundant. Migrate KeyPath's device config to use `definputdevices` instead:

```
;; Before (KeyPath fork feature):
(defcfg
  macos-dev-ids-include ("00DE:5754"))

;; After (upstream definputdevices):
(definputdevices
  (device 1 (vendor_id 0x00DE) (product_id 0x5754)))
```

## Commit count trajectory

| State | Commits |
|-------|---------|
| Current | 15 |
| After open PRs merge + auto-drops | 5 |
| After filing & merging small PRs | 3 |

## Reduction sequence

1. **Wait for PR #2070 (managed-repeat) to merge** — drops 5 commits
2. **Wait for PR #2065 (continue-if-no-devs) to merge** — drops 2 commits + 3 auto-drop docs
3. **File PR for VirtualHID timeout** — drops 1 commit
4. **File PR for VID:PID in --list** — drops 1 commit
5. **Target state: 3 fork-only commits** (TCP broadcast, TapHoldReason tracing, --json)
