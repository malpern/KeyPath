#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Quick Launcher — activation-mode and hyper-trigger variants.
# Every successful `config apply` is also a kanata syntax check (the CLI
# validates with the bundled kanata before applying).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"

apply_launcher() {
  local activation_mode="$1" hyper_trigger="$2"

  python3 - "$COLLECTIONS_JSON" "$activation_mode" "$hyper_trigger" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
activation_mode = sys.argv[2]
hyper_trigger = sys.argv[3]

payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

for collection in collections:
    if collection.get("name") == "Quick Launcher":
        collection["isEnabled"] = True
        configuration = collection.get("configuration") or {}
        if configuration.get("type") != "launcherGrid":
            raise SystemExit(f"Unexpected configuration type: {configuration.get('type')}")
        configuration["activationMode"] = activation_mode
        configuration["hyperTriggerMode"] = hyper_trigger
        collection["configuration"] = configuration
        break
else:
    raise SystemExit("Quick Launcher collection not found")

path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

  apply_config
}

smoke_init

echo "==> case 1: holdHyper + hold"
apply_launcher "holdHyper" "hold"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "holdHyper+hold config emits launcher action aliases"
assert_contains "$config" "(layer-while-held launcher)" "holdHyper+hold activates launcher while held"

echo "==> case 2: holdHyper + tap"
apply_launcher "holdHyper" "tap"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "holdHyper+tap config emits launcher action aliases"

echo "==> case 3: leaderSequence"
apply_launcher "leaderSequence" "hold"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "leaderSequence config emits launcher action aliases"

echo "Quick Launcher smoke passed. Restoring original KeyPath config."
