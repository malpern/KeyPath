#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Window Snapping — enables the collection and asserts the
# window action push-msgs reach the generated config (standard convention).
#
# Note: the vim key convention is covered at the unit level by
# PerOptionMatrixTests. Flipping `windowKeyConvention` in RuleCollections.json
# alone does not regenerate the stored mappings (the UI does that on change),
# so a JSON-only flip would assert against stale mappings — intentionally not
# attempted here.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/qa-smoke-lib.sh"

enable_window_snapping() {
  python3 - "$COLLECTIONS_JSON" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
collections = payload.get("collections")
if not isinstance(collections, list):
    raise SystemExit("RuleCollections.json does not contain a collections array")

for collection in collections:
    if collection.get("name") == "Window Snapping":
        collection["isEnabled"] = True
        break
else:
    raise SystemExit("Window Snapping collection not found")

path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  apply_config
}

smoke_init

echo "==> enable Window Snapping (standard convention)"
enable_window_snapping
config="$(show_config)"
assert_contains "$config" 'window:left' "window snapping config emits window:left push-msg"
assert_contains "$config" 'window:right' "window snapping config emits window:right push-msg"
assert_contains "$config" "act_window_" "window snapping config emits window action aliases"

echo "Window Snapping smoke passed. Restoring original KeyPath config."
