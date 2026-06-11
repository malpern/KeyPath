#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Home Row Layer Toggles — exercises both modes (whileHeld
# and toggle) and asserts the generated kanata config is well-formed.
#
# The toggle-mode-alone case specifically exercises the stub-deflayer safety
# net (PR #871) — referenced layers (`fun`, `sym`, `num`) are owned by
# Function/Symbol/Numpad which aren't enabled by default. Pre-#871 this
# combination produced a config kanata rejected.

CLI="${KEYPATH_CLI:-/Applications/KeyPath.app/Contents/MacOS/keypath-cli}"
CONFIG_DIR="${KEYPATH_CONFIG_DIR:-$HOME/.config/keypath}"
COLLECTIONS_JSON="$CONFIG_DIR/RuleCollections.json"
TMP_DIR="$(mktemp -d)"
BACKUP_PATH=""

cleanup() {
  local status=$?
  if [[ -n "$BACKUP_PATH" ]]; then
    "$CLI" config restore --json --quiet "$BACKUP_PATH" --reload >/dev/null || {
      echo "warning: failed to restore KeyPath config from $BACKUP_PATH" >&2
    }
  fi
  rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "error: required file not found: $1" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "error: $label did not contain expected snippet:" >&2
    echo "  $needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "error: $label unexpectedly contained snippet:" >&2
    echo "  $needle" >&2
    exit 1
  fi
}

# Apply a desired enabled-state to a set of collections and (optionally)
# flip HRL Toggles' toggleMode. Identifies collections by name to stay
# robust against UUID drift.
apply_state() {
  local toggle_mode="$1"      # whileHeld | toggle
  local enable_companions="$2" # true | false

  python3 - "$COLLECTIONS_JSON" "$toggle_mode" "$enable_companions" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
toggle_mode = sys.argv[2]
enable_companions = sys.argv[3] == "true"

payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

companion_names = {"Function", "Symbol", "Numpad"}
found_hrl = False

for collection in collections:
    name = collection.get("name")
    if name == "Home Row Layer Toggles":
        found_hrl = True
        collection["isEnabled"] = True
        configuration = collection.get("configuration") or {}
        if configuration.get("type") != "homeRowLayerToggles":
            raise SystemExit(
                f"Unexpected configuration type for HRL Toggles: {configuration.get('type')}"
            )
        configuration["toggleMode"] = toggle_mode
        collection["configuration"] = configuration
    elif name in companion_names:
        collection["isEnabled"] = enable_companions

if not found_hrl:
    raise SystemExit("Home Row Layer Toggles collection not found")

path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

  "$CLI" config apply --json --quiet >/dev/null
}

show_config() {
  "$CLI" config show --no-json --quiet
}

require_file "$CLI"
require_file "$COLLECTIONS_JSON"

backup_json="$("$CLI" config backup --json --quiet --output "$TMP_DIR/keypath-config-backup")"
BACKUP_PATH="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["data"]["backupPath"])' <<< "$backup_json")"

echo "==> case 1: HRL Toggles whileHeld mode, companions disabled"
apply_state "whileHeld" "false"
config="$(show_config)"
assert_contains "$config" "(layer-while-held" "whileHeld config emits the whileHeld action"
assert_not_contains "$config" "(layer-toggle " "whileHeld config does not emit layer-toggle"

echo "==> case 2: HRL Toggles toggle mode, companions disabled (stub-deflayer safety net)"
apply_state "toggle" "false"
config="$(show_config)"
assert_contains "$config" "(layer-toggle " "toggle config emits the layer-toggle action"
# The catalog default assignments hit fun, sym, num — those must end up
# as deflayer blocks (real OR stubbed) so kanata accepts the config.
assert_contains "$config" "(deflayer fun" "stub or real deflayer fun emitted"
assert_contains "$config" "(deflayer sym" "stub or real deflayer sym emitted"
assert_contains "$config" "(deflayer num" "stub or real deflayer num emitted"

echo "==> case 3: HRL Toggles toggle mode, companions ENABLED (no stubs needed)"
apply_state "toggle" "true"
config="$(show_config)"
assert_contains "$config" "(layer-toggle " "companion mode emits layer-toggle"
assert_contains "$config" "(deflayer fun" "real Function deflayer emitted"
assert_contains "$config" "(deflayer sym" "real Symbol deflayer emitted"
assert_contains "$config" "(deflayer num" "real Numpad deflayer emitted"
# When companions are enabled, the deflayers should have real content,
# not just transparent stubs. Check for any non-transparent token in
# the fun layer block (rough heuristic: stub layers are all "_").
fun_layer_block="$(printf '%s\n' "$config" | awk '/^\(deflayer fun/{flag=1} flag; /^\)/{if (flag) exit}')"
if [[ "$fun_layer_block" =~ ^[[:space:]_()defalyrun]+$ ]]; then
  echo "error: real Function layer appears to contain only transparent placeholders" >&2
  echo "$fun_layer_block" >&2
  exit 1
fi

echo "HRL Toggles smoke passed. Restoring original KeyPath config."
