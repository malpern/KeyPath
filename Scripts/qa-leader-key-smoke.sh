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

# Issue #889: the standalone `keypath-cli config apply` path now reconciles the
# leader key from the Leader Key collection's selectedOutput. Previously it read
# leaderKeyPreference directly (via ConfigFacade → ConfigurationService) and never
# constructed a RuleCollectionsManager, so the picker was display-only from the CLI.
# ConfigFacade.applyConfiguration now reconciles both the leaderKeyPreference and the
# base→nav leader activator before generating config (LeaderKeyPreference.reconciled /
# .reconcileLeaderActivators), so each preset drives its own leader binding.
#
# The generated config annotates the primary leader with a "Primary Leader Key
# (System Preference)" block whose activator renders as ";; Input: <key>". We assert
# the reconciled key drives that binding for each preset.
#
# NOTE: still deferred to #865/#888 — a headless edit that *disables* a previously
# reconciled collection leaves leaderKeyPreference stale (disable-drift), and full
# single-source-of-truth generation from the collection.
for preset in space caps tab grv; do
  echo "==> preset: $preset"
  apply_leader "$preset"
  config="$(show_config)"
  assert_contains "$config" "Leader Key" "preset $preset config includes the Leader Key collection"
  assert_contains "$config" ";; Input: $preset" "preset $preset drives its own leader binding (#889)"
done

echo "Leader Key smoke passed (all 4 presets drive their own CLI-generated leader binding). Restoring original KeyPath config."
