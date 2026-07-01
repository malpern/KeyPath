#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Leader Key — exercises all four singleKeyPicker presets
# (space, caps, tab, grave) and asserts the generated config applies cleanly
# (kanata-validated by the CLI) for each.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"

apply_leader() {
  local selected_output="$1"

  python3 - "$COLLECTIONS_JSON" "$selected_output" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
selected_output = sys.argv[2]

payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

for collection in collections:
    if collection.get("name") == "Leader Key":
        collection["isEnabled"] = True
        configuration = collection.get("configuration") or {}
        if configuration.get("type") != "singleKeyPicker":
            raise SystemExit(f"Unexpected configuration type: {configuration.get('type')}")
        valid = {opt.get("output") for opt in configuration.get("presetOptions", [])}
        if selected_output not in valid:
            raise SystemExit(f"Preset {selected_output!r} not in presetOptions {sorted(valid)}")
        configuration["selectedOutput"] = selected_output
        collection["configuration"] = configuration
        break
else:
    raise SystemExit("Leader Key collection not found")

path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  apply_config
}

smoke_init

# Fixed (issue #889): the Leader Key collection's selectedOutput is now the
# source of truth for the leader binding even on the headless path. Loading
# collections reconciles the system leaderKeyPreference from the collection
# (RuleCollectionsManager.reconcileLeaderKeyFromCollection), so JSON/CLI
# mutation of selectedOutput actually changes the generated config. Each
# preset must emit its own leader input, not the default.
for preset in space caps tab grv; do
  echo "==> preset: $preset"
  apply_leader "$preset"
  config="$(show_config)"
  assert_contains "$config" "Leader Key" "preset $preset config includes the Leader Key collection"
  assert_contains "$config" ";; Input: $preset" "preset $preset drives the generated leader binding"
done

echo "Leader Key smoke passed (all 4 presets drive their own leader binding, kanata-clean). Restoring original KeyPath config."
