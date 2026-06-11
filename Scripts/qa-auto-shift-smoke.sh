#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Auto Shift Symbols — timeout, fast-typing protection, and
# reduced key-set variants, asserted against the generated kanata config.
# Distinctive timeout values (173 / 247) anchor the digit assertions so they
# can't false-match unrelated timing constants.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"

apply_auto_shift() {
  local timeout_ms="$1" protect="$2" enabled_keys_json="$3"

  python3 - "$COLLECTIONS_JSON" "$timeout_ms" "$protect" "$enabled_keys_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
timeout_ms = int(sys.argv[2])
protect = sys.argv[3] == "true"
enabled_keys = json.loads(sys.argv[4])

payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

for collection in collections:
    if collection.get("name") == "Auto Shift Symbols":
        collection["isEnabled"] = True
        configuration = collection.get("configuration") or {}
        if configuration.get("type") != "autoShiftSymbols":
            raise SystemExit(f"Unexpected configuration type: {configuration.get('type')}")
        configuration["timeoutMs"] = timeout_ms
        configuration["protectFastTyping"] = protect
        configuration["enabledKeys"] = enabled_keys
        collection["configuration"] = configuration
        break
else:
    raise SystemExit("Auto Shift Symbols collection not found")

path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  apply_config
}

smoke_init

all_keys='["grv","min","eql","lbrc","rbrc","bsls","scln","apos","comm","dot","slsh"]'

echo "==> case 1: protect on, timeout 173, all keys"
apply_auto_shift 173 true "$all_keys"
config="$(show_config)"
assert_contains "$config" "require-prior-idle 173" "protect-on config"
assert_contains "$config" "beh_base_dot" "protect-on config"
assert_contains "$config" "beh_base_grv" "protect-on config"

echo "==> case 2: protect off, timeout 173"
apply_auto_shift 173 false "$all_keys"
config="$(show_config)"
assert_not_contains "$config" "require-prior-idle 173" "protect-off config"
assert_contains "$config" "beh_base_dot" "protect-off config"

echo "==> case 3: reduced key set (dot, comm), timeout 247"
apply_auto_shift 247 true '["dot","comm"]'
config="$(show_config)"
assert_contains "$config" "beh_base_dot" "reduced-keys config"
assert_contains "$config" "beh_base_comm" "reduced-keys config"
assert_not_contains "$config" "beh_base_grv" "reduced-keys config"
assert_not_contains "$config" "beh_base_slsh" "reduced-keys config"
assert_contains "$config" "require-prior-idle 247" "reduced-keys config encodes the 247ms timeout"

echo "Auto Shift smoke passed. Restoring original KeyPath config."
