#!/usr/bin/env bash
set -euo pipefail

# Parses installer reliability matrix results from an existing test log,
# instead of re-running tests. This replaces run-installer-reliability-matrix.sh
# in CI to avoid redundant swift test invocations.
#
# Usage: ./Scripts/parse-installer-matrix.sh <test-log-file>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

LOG_FILE="${1:-test_output.safe.txt}"
OUT_ROOT="test-results/installer-reliability"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT_DIR="$OUT_ROOT/$TIMESTAMP_UTC"

mkdir -p "$OUT_DIR"

if [ ! -f "$LOG_FILE" ]; then
  echo "Test log not found: $LOG_FILE"
  echo "Skipping matrix parsing."
  exit 0
fi

json_escape() {
    printf '%s' "$1" \
        | perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# Lane definitions: id, name, test class patterns (pipe-separated)
declare -a LANE_IDS=(preflight mutation postflight)
declare -a LANE_NAMES=(
  "Pre-install requirements and plan construction"
  "Install/repair mutations and lifecycle postconditions"
  "Post-install health and broker routing checks"
)
declare -a LANE_PATTERNS=(
  "InstallerEnginePlanTests|InstallerEngineTests|SystemValidatorTests"
  "InstallerEngineEndToEndTests|InstallerEngineSingleActionRoutingTests|PrivilegedOperationsCoordinatorTests|ServiceBootstrapperTests"
  "InstallerEngineHealthCheckTests|InstallerEngineBrokerForwardingTests|WizardRecipeParityTests"
)

declare -a LANE_STATUSES=()
declare -a LANE_PASS_COUNTS=()
declare -a LANE_FAIL_COUNTS=()
declare -a LANE_SUMMARIES=()
total_parsed=0

echo "Parsing installer reliability matrix from: $LOG_FILE"
echo "Output: $OUT_DIR"
echo ""

for i in "${!LANE_IDS[@]}"; do
  lane_id="${LANE_IDS[$i]}"
  lane_name="${LANE_NAMES[$i]}"
  pattern="${LANE_PATTERNS[$i]}"

  # Count passes and failures for test classes matching this lane's pattern.
  # XCTest format: Test Case '-[Module.ClassName testMethod]' passed/failed
  # Swift Testing format: Test "ClassName/testMethod" passed/failed after ...
  # Uses [. ] before class name to anchor match and prevent substring contamination
  # (e.g. "InstallerEngineTests" won't match "InstallerEngineEndToEndTests").
  pass_count=$(grep -cE "(Test Case '.*[. ]($pattern) .*' passed|Test \"($pattern)[/\"].*passed)" "$LOG_FILE" 2>/dev/null || echo 0)
  fail_count=$(grep -cE "(Test Case '.*[. ]($pattern) .*' failed|Test \"($pattern)[/\"].*failed)" "$LOG_FILE" 2>/dev/null || echo 0)

  if [ "$fail_count" -gt 0 ]; then
    status="fail"
    summary="$pass_count passed, $fail_count failed"
  elif [ "$pass_count" -gt 0 ]; then
    status="pass"
    summary="$pass_count passed"
  else
    status="skip"
    summary="No matching tests found in log"
  fi

  LANE_STATUSES+=("$status")
  LANE_PASS_COUNTS+=("$pass_count")
  LANE_FAIL_COUNTS+=("$fail_count")
  LANE_SUMMARIES+=("$summary")
  total_parsed=$((total_parsed + pass_count + fail_count))

  echo "  [$lane_id] $lane_name: $status ($summary)"

  # Extract relevant log lines for this lane
  grep -E "($pattern)" "$LOG_FILE" > "$OUT_DIR/lane-${lane_id}.log" 2>/dev/null || true
done

# Sanity check: verify the parser found at least some installer tests.
# The matrix only covers installer-related test classes (a small subset of all tests),
# so we check whether the parser found zero when installer test classes appear in the log.
# (total_parsed is accumulated in the loop above)
# Check if any installer test classes appear in the log at all
all_patterns=$(printf "%s|" "${LANE_PATTERNS[@]}" | sed 's/|$//')
installer_mentions=$(grep -cE "$all_patterns" "$LOG_FILE" 2>/dev/null || echo 0)
if [ "$installer_mentions" -gt 0 ] && [ "$total_parsed" -eq 0 ]; then
  echo "ERROR: Log mentions installer test classes ($installer_mentions lines) but parser matched 0 pass/fail results."
  echo "The xctest output format may have changed — review grep patterns in this script."
  exit 1
fi
echo "  Sanity check: parsed $total_parsed results from $installer_mentions installer-related log lines"

# Count failures
failed_lanes=0
for status in "${LANE_STATUSES[@]}"; do
  if [ "$status" = "fail" ]; then
    failed_lanes=$((failed_lanes + 1))
  fi
done

if [ "$failed_lanes" -eq 0 ]; then
  overall_status="pass"
else
  overall_status="fail"
fi

# Write JSON report
{
  echo "{"
  echo "  \"generatedAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"outputDirectory\": \"$(json_escape "$OUT_DIR")\","
  echo "  \"overallStatus\": \"$(json_escape "$overall_status")\","
  echo "  \"failedLaneCount\": $failed_lanes,"
  echo "  \"parsedFromLog\": \"$(json_escape "$LOG_FILE")\","
  echo "  \"lanes\": ["

  for i in "${!LANE_IDS[@]}"; do
    comma=","
    if [ "$i" -eq "$((${#LANE_IDS[@]} - 1))" ]; then
      comma=""
    fi
    echo "    {"
    echo "      \"id\": \"$(json_escape "${LANE_IDS[$i]}")\","
    echo "      \"name\": \"$(json_escape "${LANE_NAMES[$i]}")\","
    echo "      \"filter\": \"$(json_escape "${LANE_PATTERNS[$i]}")\","
    echo "      \"status\": \"$(json_escape "${LANE_STATUSES[$i]}")\","
    echo "      \"passCount\": ${LANE_PASS_COUNTS[$i]},"
    echo "      \"failCount\": ${LANE_FAIL_COUNTS[$i]},"
    echo "      \"summary\": \"$(json_escape "${LANE_SUMMARIES[$i]}")\""
    echo "    }$comma"
  done

  echo "  ]"
  echo "}"
} > "$OUT_DIR/matrix-results.json"

# Write Markdown summary
{
  echo "## Installer Reliability Matrix"
  echo ""
  echo "- Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
  echo "- Source: \`$LOG_FILE\` (parsed, not re-run)"
  echo "- Overall: **$overall_status**"
  echo "- Failed lanes: **$failed_lanes**"
  echo ""
  echo "| Lane | Scope | Status | Results |"
  echo "| --- | --- | --- | --- |"

  for i in "${!LANE_IDS[@]}"; do
    echo "| \`${LANE_IDS[$i]}\` | ${LANE_NAMES[$i]} | ${LANE_STATUSES[$i]} | ${LANE_SUMMARIES[$i]} |"
  done
} > "$OUT_DIR/matrix-summary.md"

mkdir -p "$OUT_ROOT"
ln -sfn "$TIMESTAMP_UTC" "$OUT_ROOT/latest"

echo ""
echo "Matrix artifacts written to $OUT_DIR"

if [ "$failed_lanes" -ne 0 ]; then
  echo "Installer reliability matrix failed ($failed_lanes lane(s) failed)."
  exit 1
fi

echo "Installer reliability matrix passed."
