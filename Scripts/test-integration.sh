#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
source "$SCRIPT_DIR/lib/test-lanes.sh"

filter=$(keypath_test_lane_filter integration)
echo "🧪 test-integration"
echo "🎯 filter: $filter"
TEST_FILTER="$filter" "$SCRIPT_DIR/run-tests-safe.sh"
