#!/usr/bin/env bash
set -euo pipefail

# Runs a focused installer reliability matrix and emits a concise artifact bundle.
# Usage:
#   ./Scripts/run-installer-reliability-matrix.sh [output-root]
# Example:
#   ./Scripts/run-installer-reliability-matrix.sh test-results/installer-reliability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

OUT_ROOT="${1:-test-results/installer-reliability}"
OUT_ROOT="${OUT_ROOT%/}"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT_DIR="$OUT_ROOT/$TIMESTAMP_UTC"

mkdir -p "$OUT_DIR"

json_escape() {
    printf '%s' "$1" \
        | perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

capture_context() {
    {
        echo "generated_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "git_commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "git_branch=$(git branch --show-current 2>/dev/null || echo unknown)"
        echo "swift_version=$(swift --version | head -n 1)"
        if command -v sw_vers >/dev/null 2>&1; then
            echo "macos_version=$(sw_vers -productVersion)"
            echo "macos_build=$(sw_vers -buildVersion)"
        fi
        echo "hostname=$(hostname)"
    } > "$OUT_DIR/run-context.txt"
}

run_lane() {
    local lane_id="$1"
    local lane_name="$2"
    local lane_filter="$3"

    local lane_log="$OUT_DIR/lane-${lane_id}.log"
    local start_seconds
    local end_seconds
    local elapsed_seconds
    local exit_code
    local summary_line
    local status

    echo
    echo "==> [$lane_id] $lane_name"
    echo "    filter: $lane_filter"

    start_seconds="$(date +%s)"
    set +e
    KEYPATH_USE_INSTALLER_ENGINE=1 \
    SKIP_EVENT_TAP_TESTS=1 \
    SWIFT_TEST=1 \
    CI_ENVIRONMENT="${CI_ENVIRONMENT:-false}" \
    swift test --filter "$lane_filter" 2>&1 | tee "$lane_log"
    exit_code=${PIPESTATUS[0]}
    set -e
    end_seconds="$(date +%s)"
    elapsed_seconds=$((end_seconds - start_seconds))

    summary_line="$(grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?" "$lane_log" | tail -n 1 || true)"
    if [ -z "$summary_line" ]; then
        summary_line="$(grep -E "Test Suite 'All tests' .*" "$lane_log" | tail -n 1 || true)"
    fi
    if [ -z "$summary_line" ]; then
        summary_line="No XCTest summary line captured."
    fi

    if [ "$exit_code" -eq 0 ]; then
        status="pass"
    else
        status="fail"
    fi

    local executed_tests
    executed_tests="$(grep -Eo "Executed [0-9]+ tests?" "$lane_log" | tail -n 1 | awk '{print $2}' || true)"
    if [ "$exit_code" -eq 0 ] && [ -n "$executed_tests" ] && [ "$executed_tests" -eq 0 ]; then
        status="fail"
        exit_code=97
        summary_line="$summary_line (no tests matched filter)"
    fi

    # Swift Testing emits "0 tests in 0 suites passed" instead of XCTest format.
    # Catch this to prevent false-green lanes when no tests match the filter.
    if [ "$exit_code" -eq 0 ] && [ "$status" = "pass" ]; then
        local swift_testing_zero
        swift_testing_zero="$(grep -E "0 tests? .* 0 suites? passed" "$lane_log" | head -n 1 || true)"
        if [ -n "$swift_testing_zero" ]; then
            status="fail"
            exit_code=97
            summary_line="$summary_line (no Swift Testing tests matched filter)"
        fi
    fi

    LANE_IDS+=("$lane_id")
    LANE_NAMES+=("$lane_name")
    LANE_FILTERS+=("$lane_filter")
    LANE_LOGS+=("$lane_log")
    LANE_SUMMARIES+=("$summary_line")
    LANE_EXIT_CODES+=("$exit_code")
    LANE_DURATIONS+=("$elapsed_seconds")
    LANE_STATUSES+=("$status")

    echo "    status: $status (exit=$exit_code, duration=${elapsed_seconds}s)"
}

run_diagnostics_snapshot() {
    DIAGNOSTIC_LOG="$OUT_DIR/inspect-snapshot.log"
    echo
    echo "==> [diagnostic] Capturing inspect snapshot"
    set +e
    KEYPATH_USE_INSTALLER_ENGINE=1 \
    SKIP_EVENT_TAP_TESTS=1 \
    SWIFT_TEST=1 \
    CI_ENVIRONMENT="${CI_ENVIRONMENT:-false}" \
    swift run keypath-cli inspect >"$DIAGNOSTIC_LOG" 2>&1
    DIAGNOSTIC_EXIT_CODE=$?
    set -e

    if [ "$DIAGNOSTIC_EXIT_CODE" -eq 0 ]; then
        DIAGNOSTIC_STATUS="pass"
    else
        DIAGNOSTIC_STATUS="warn"
    fi
    echo "    status: $DIAGNOSTIC_STATUS (exit=$DIAGNOSTIC_EXIT_CODE)"
}

write_json_report() {
    local report_file="$OUT_DIR/matrix-results.json"
    local overall_status="$1"
    local failed_lanes="$2"

    {
        echo "{"
        echo "  \"generatedAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"outputDirectory\": \"$(json_escape "$OUT_DIR")\","
        echo "  \"overallStatus\": \"$(json_escape "$overall_status")\","
        echo "  \"failedLaneCount\": $failed_lanes,"
        echo "  \"lanes\": ["

        local i
        for i in "${!LANE_IDS[@]}"; do
            local comma=","
            if [ "$i" -eq "$((${#LANE_IDS[@]} - 1))" ]; then
                comma=""
            fi
            echo "    {"
            echo "      \"id\": \"$(json_escape "${LANE_IDS[$i]}")\","
            echo "      \"name\": \"$(json_escape "${LANE_NAMES[$i]}")\","
            echo "      \"filter\": \"$(json_escape "${LANE_FILTERS[$i]}")\","
            echo "      \"status\": \"$(json_escape "${LANE_STATUSES[$i]}")\","
            echo "      \"exitCode\": ${LANE_EXIT_CODES[$i]},"
            echo "      \"durationSeconds\": ${LANE_DURATIONS[$i]},"
            echo "      \"summary\": \"$(json_escape "${LANE_SUMMARIES[$i]}")\","
            echo "      \"logPath\": \"$(json_escape "${LANE_LOGS[$i]}")\""
            echo "    }$comma"
        done

        echo "  ],"
        echo "  \"diagnosticSnapshot\": {"
        echo "    \"command\": \"swift run keypath-cli inspect\","
        echo "    \"status\": \"$(json_escape "$DIAGNOSTIC_STATUS")\","
        echo "    \"exitCode\": $DIAGNOSTIC_EXIT_CODE,"
        echo "    \"logPath\": \"$(json_escape "$DIAGNOSTIC_LOG")\""
        echo "  }"
        echo "}"
    } > "$report_file"
}

write_markdown_summary() {
    local summary_file="$OUT_DIR/matrix-summary.md"
    local overall_status="$1"
    local failed_lanes="$2"

    {
        echo "## Installer Reliability Matrix"
        echo
        echo "- Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
        echo "- Output: \`$OUT_DIR\`"
        echo "- Overall: **$overall_status**"
        echo "- Failed lanes: **$failed_lanes**"
        echo
        echo "| Lane | Scope | Status | Duration (s) | XCTest Summary |"
        echo "| --- | --- | --- | ---: | --- |"

        local i
        for i in "${!LANE_IDS[@]}"; do
            echo "| \`${LANE_IDS[$i]}\` | ${LANE_NAMES[$i]} | ${LANE_STATUSES[$i]} | ${LANE_DURATIONS[$i]} | ${LANE_SUMMARIES[$i]} |"
        done

        echo
        echo "### Diagnostic Snapshot"
        echo
        echo "- Command: \`swift run keypath-cli inspect\`"
        echo "- Status: **$DIAGNOSTIC_STATUS** (exit $DIAGNOSTIC_EXIT_CODE)"
        echo "- Log: \`$DIAGNOSTIC_LOG\`"
    } > "$summary_file"
}

declare -a LANE_IDS=()
declare -a LANE_NAMES=()
declare -a LANE_FILTERS=()
declare -a LANE_LOGS=()
declare -a LANE_SUMMARIES=()
declare -a LANE_EXIT_CODES=()
declare -a LANE_DURATIONS=()
declare -a LANE_STATUSES=()

DIAGNOSTIC_STATUS="warn"
DIAGNOSTIC_EXIT_CODE=1
DIAGNOSTIC_LOG="$OUT_DIR/inspect-snapshot.log"

echo "🧭 Running installer reliability matrix..."
echo "Output root: $OUT_ROOT"
echo "Run directory: $OUT_DIR"

capture_context

run_lane \
    "preflight" \
    "Pre-install requirements and plan construction" \
    "InstallerEnginePlanTests|InstallerEngineTests|SystemValidatorTests"
run_lane \
    "mutation" \
    "Install/repair mutations and lifecycle postconditions" \
    "InstallerEngineEndToEndTests|InstallerEngineSingleActionRoutingTests|PrivilegedOperationsCoordinatorTests|ServiceBootstrapperTests"
run_lane \
    "postflight" \
    "Post-install health and broker routing checks" \
    "InstallerEngineHealthCheckTests|InstallerEngineBrokerForwardingTests|WizardRecipeParityTests"

run_diagnostics_snapshot

failed_lanes=0
for status in "${LANE_STATUSES[@]}"; do
    if [ "$status" != "pass" ]; then
        failed_lanes=$((failed_lanes + 1))
    fi
done

if [ "$failed_lanes" -eq 0 ]; then
    overall_status="pass"
else
    overall_status="fail"
fi

write_json_report "$overall_status" "$failed_lanes"
write_markdown_summary "$overall_status" "$failed_lanes"

mkdir -p "$OUT_ROOT"
ln -sfn "$TIMESTAMP_UTC" "$OUT_ROOT/latest"

echo
echo "✅ Matrix artifacts written:"
echo "   - $OUT_DIR/matrix-summary.md"
echo "   - $OUT_DIR/matrix-results.json"
echo "   - $OUT_DIR/run-context.txt"
echo "   - $OUT_DIR/lane-*.log"
echo "   - $OUT_DIR/inspect-snapshot.log"
echo "   - $OUT_ROOT/latest -> $TIMESTAMP_UTC"

if [ "$failed_lanes" -ne 0 ]; then
    echo "❌ Installer reliability matrix failed ($failed_lanes lane(s) failed)."
    exit 1
fi

echo "✅ Installer reliability matrix passed."
