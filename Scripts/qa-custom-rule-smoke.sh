#!/usr/bin/env bash
set -euo pipefail

# Smoke test for custom rules — drives the CLI rule commands end-to-end:
# simple remap, tap-hold (dual-role), then removal. Asserts the mapping
# reaches the generated kanata config and disappears after removal.
#
# Uses number-row keys (9, 8) that no catalog default maps, so the test
# doesn't trip the collision detector against system-default collections.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"

smoke_init

# `rule add/remove` mutate CustomRules.json; the .kbd only regenerates on
# `config apply`, so each case applies explicitly before asserting.

echo "==> case 1: simple remap 9 -> 0"
"$CLI" rule add 9 0 --on-conflict replace --json --quiet >/dev/null
apply_config
config="$(show_config)"
assert_contains "$config" "Collection: 9 → 0" "simple remap appears as a custom rule collection"

echo "==> case 2: tap-hold on 8 (tap 8, hold lctl)"
"$CLI" rule add 8 --tap 8 --hold lctl --on-conflict replace --json --quiet >/dev/null
apply_config
config="$(show_config)"
assert_contains "$config" "tap-hold" "tap-hold rule emits a tap-hold action"
assert_contains "$config" "lctl" "tap-hold rule emits the hold modifier"

echo "==> case 3: removal"
"$CLI" rule remove 9 --json --quiet >/dev/null
"$CLI" rule remove 8 --json --quiet >/dev/null
apply_config
config="$(show_config)"
assert_not_contains "$config" "Collection: 9 → 0" "config after removal"

echo "Custom rule smoke passed. Restoring original KeyPath config."
