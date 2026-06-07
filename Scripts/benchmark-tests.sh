#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
cd "$REPO_ROOT"

FILTER="${TEST_FILTER:-${1:-fast}}"
WORKERS="${TEST_PARALLEL_WORKERS:-8}"
OUT_ROOT="${TEST_BENCHMARK_OUT:-test-results/test-benchmarks}"
STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUT_DIR="$OUT_ROOT/$STAMP"
mkdir -p "$OUT_DIR"

if [[ "$FILTER" == "full" ]]; then
    FILTER_VALUE=""
else
    source "$SCRIPT_DIR/lib/test-lanes.sh"
    if lane_filter=$(keypath_test_lane_filter "$FILTER" 2>/dev/null); then
        FILTER_VALUE="$lane_filter"
    else
        FILTER_VALUE="$FILTER"
    fi
fi

run_case() {
    local name="$1"
    local extra_args="$2"
    local log="$OUT_DIR/${name}.log"
    local start
    local end
    local status=0

    echo
    echo "==> $name"
    echo "    filter: ${FILTER_VALUE:-full suite}"
    echo "    extra args: ${extra_args:-none}"
    start=$(date +%s)
    set +e
    if [[ -n "$FILTER_VALUE" ]]; then
        TEST_FILTER="$FILTER_VALUE" SWIFT_TEST_ARGS="$extra_args" "$SCRIPT_DIR/run-tests-safe.sh" 2>&1 | tee "$log"
    else
        SWIFT_TEST_ARGS="$extra_args" "$SCRIPT_DIR/run-tests-safe.sh" 2>&1 | tee "$log"
    fi
    status=${PIPESTATUS[0]}
    set -e
    end=$(date +%s)
    echo "$((end - start))" > "$OUT_DIR/${name}.seconds"
    echo "$status" > "$OUT_DIR/${name}.exit"
    return "$status"
}

default_status=0
parallel_status=0
run_case default "" || default_status=$?
run_case parallel "--parallel --num-workers $WORKERS" || parallel_status=$?

default_seconds=$(cat "$OUT_DIR/default.seconds")
parallel_seconds=$(cat "$OUT_DIR/parallel.seconds")

cat > "$OUT_DIR/summary.md" <<EOF
# Test Benchmark

- Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Filter: ${FILTER_VALUE:-full suite}
- Parallel workers: $WORKERS
- Default: ${default_seconds}s (exit $default_status)
- Parallel: ${parallel_seconds}s (exit $parallel_status)
EOF

ln -sfn "$STAMP" "$OUT_ROOT/latest"

echo
echo "Benchmark artifacts written to $OUT_DIR"
cat "$OUT_DIR/summary.md"

if [[ "$default_status" -ne 0 || "$parallel_status" -ne 0 ]]; then
    exit 1
fi
