#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
source "$SCRIPT_DIR/lib/test-lanes.sh"

filter=$(keypath_test_lane_filter visual)
echo "🧪 test-visual"
echo "🎯 filter: $filter"
KEYPATH_SNAPSHOTS=1 TEST_FILTER="$filter" "$SCRIPT_DIR/run-tests-safe.sh"
