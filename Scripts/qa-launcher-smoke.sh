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

path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  apply_config
}

smoke_init

echo "==> case 1: holdHyper + hold"
apply_launcher "holdHyper" "hold"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "holdHyper+hold config emits launcher action aliases"
assert_contains "$config" "(layer-while-held launcher)" "holdHyper+hold activates launcher while held"
assert_not_contains "$config" "one-shot-press 5000 (layer-while-held launcher)" "hold mode does not wrap activation in a one-shot"

echo "==> case 2: holdHyper + tap"
apply_launcher "holdHyper" "tap"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "holdHyper+tap config emits launcher action aliases"
# Tap mode wraps the launcher activation in a one-shot so a tap toggles the
# layer until the next key, instead of requiring a continuous hold.
assert_contains "$config" "one-shot-press 5000 (layer-while-held launcher)" "tap mode wraps activation in a one-shot"

echo "==> case 3: leaderSequence"
apply_launcher "leaderSequence" "hold"
config="$(show_config)"
assert_contains "$config" "act_launcher_" "leaderSequence config emits launcher action aliases"
# Finding (release-readiness, Thu): activationMode=leaderSequence currently
# generates a config byte-identical to holdHyper+hold — the Hyper hold path
# stays active. Whether that's intended (both routes coexist) is a design
# review question; until resolved this case asserts apply-success only.

echo "Quick Launcher smoke passed. Restoring original KeyPath config."
