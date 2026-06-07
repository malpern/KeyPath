#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)

echo "🧪 test-full"
KEYPATH_SNAPSHOTS=1 "$SCRIPT_DIR/run-tests-safe.sh"
