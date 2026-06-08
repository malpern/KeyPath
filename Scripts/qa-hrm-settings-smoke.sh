#!/usr/bin/env bash
set -euo pipefail

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

apply_hrm_case() {
  local hold_mode="$1"
  local opposite_hand_mode="$2"
  local layer_toggle_mode="$3"
  local enabled_keys_json="$4"
  local timing_json="$5"

  python3 - "$COLLECTIONS_JSON" "$hold_mode" "$opposite_hand_mode" "$layer_toggle_mode" "$enabled_keys_json" "$timing_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
hold_mode = sys.argv[2]
opposite_hand_mode = sys.argv[3]
layer_toggle_mode = sys.argv[4]
enabled_keys = json.loads(sys.argv[5])
timing = json.loads(sys.argv[6])

payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

for collection in collections:
    configuration = collection.get("configuration") or {}
    if collection.get("name") == "Home Row Mods" or configuration.get("type") == "homeRowMods":
        collection["isEnabled"] = True
        configuration.update({
            "type": "homeRowMods",
            "enabledKeys": enabled_keys,
            "modifierAssignments": {
                "a": "lsft", "s": "lctl", "d": "lalt", "f": "lmet",
                "j": "rmet", "k": "ralt", "l": "rctl", ";": "rsft",
            },
            "layerAssignments": {
                "a": "fun", "s": "num", "d": "sym", "f": "nav",
                "j": "nav", "k": "sym", "l": "num", ";": "fun",
            },
            "holdMode": hold_mode,
            "hasUserSelectedHoldMode": True,
            "layerToggleMode": layer_toggle_mode,
            "timing": timing,
            "keySelection": "custom",
            "showAdvanced": True,
            "timingMode": "precision",
            "showExpertTiming": True,
            "oppositeHandMode": opposite_hand_mode,
        })
        collection["configuration"] = configuration
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        break
else:
    raise SystemExit("Home Row Mods collection not found")
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

default_timing='{"tapWindow":200,"holdDelay":150,"quickTapEnabled":false,"quickTapTermMs":0,"tapOffsets":{},"holdOffsets":{},"requirePriorIdleMs":150}'

echo "==> modifiers with opposite-hand press"
apply_hrm_case "modifiers" "press" "whileHeld" '["a","s","d","f","j","k","l",";"]' "$default_timing"
config="$(show_config)"
assert_contains "$config" "(defhands" "opposite-hand press config"
assert_contains "$config" "beh_base_a (tap-hold-opposite-hand 150 a lsft)" "opposite-hand press config"

echo "==> modifiers with opposite-hand release"
apply_hrm_case "modifiers" "release" "whileHeld" '["a"]' "$default_timing"
config="$(show_config)"
assert_contains "$config" "beh_base_a (tap-hold-opposite-hand-release 150 a lsft)" "opposite-hand release config"

echo "==> opposite-hand off with quick tap and per-key timing"
timing='{"tapWindow":230,"holdDelay":180,"quickTapEnabled":true,"quickTapTermMs":25,"tapOffsets":{"a":40},"holdOffsets":{"a":30},"requirePriorIdleMs":220}'
apply_hrm_case "modifiers" "off" "whileHeld" '["a"]' "$timing"
config="$(show_config)"
assert_not_contains "$config" "(defhands" "opposite-hand off config"
assert_contains "$config" "tap-hold-require-prior-idle 220" "opposite-hand off config"
assert_contains "$config" "beh_base_a (tap-hold-press 295 210 a lsft)" "opposite-hand off config"

echo "==> layer hold while held"
apply_hrm_case "layers" "off" "whileHeld" '["f"]' "$default_timing"
config="$(show_config)"
assert_contains "$config" 'beh_base_f (tap-hold-press $tap-timeout 150 f (layer-while-held nav))' "layer while-held config"

echo "==> layer hold toggle"
apply_hrm_case "layers" "off" "toggle" '["f"]' "$default_timing"
config="$(show_config)"
assert_contains "$config" 'beh_base_f (tap-hold-press $tap-timeout 150 f (layer-toggle nav))' "layer toggle config"

echo "==> disabled key omitted"
apply_hrm_case "modifiers" "off" "whileHeld" '["s"]' "$default_timing"
config="$(show_config)"
assert_contains "$config" 'beh_base_s (tap-hold-press $tap-timeout 150 s lctl)' "disabled-key config"
assert_not_contains "$config" "beh_base_a" "disabled-key config"

echo "HRM settings smoke passed. Restoring original KeyPath config."

if [[ "${KEYPATH_QA_RUN_LOG_GATE:-0}" == "1" ]]; then
  "$(cd "$(dirname "$0")" && pwd)/qa-keypath-log-gate.sh"
fi
