#!/bin/bash
set -euo pipefail

# Measure local developer feedback lanes and write a small Markdown report.
# Outputs live under .build/ by default, so reports stay local-only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PRESET="quick"
OUTPUT_DIR="${KEYPATH_LOCAL_LOOP_OUT:-$PROJECT_DIR/.build/local-loop-measurements}"
CLEAN_SMOKE="${KEYPATH_LOCAL_LOOP_CLEAN_SMOKE:-0}"
CLEAN_CORE="${KEYPATH_LOCAL_LOOP_CLEAN_CORE:-0}"
LANES=()

usage() {
  cat <<'USAGE'
Usage: ./Scripts/measure-local-loop.sh [--preset quick|baseline|full] [--out DIR] [--clean-smoke] [--clean-core] [lane ...]

Presets:
  quick     Run the fastest local sanity lane: smoke.
  baseline  Run the usual MacBook Air development baseline: smoke, core-isolated, unit, appkit.
  full      Run smoke, core-isolated, unit, appkit, and full.

If explicit lanes are provided, they override the preset.

Environment:
  KEYPATH_LOCAL_LOOP_OUT          Output directory. Defaults to .build/local-loop-measurements.
  KEYPATH_LOCAL_LOOP_CLEAN_SMOKE  Set to 1 to cold-build the isolated smoke lane.
  KEYPATH_LOCAL_LOOP_CLEAN_CORE   Set to 1 to cold-build the isolated Core lane.
  TIMEOUT_SECONDS                 Passed through to safe-runner lanes.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset)
      PRESET="${2:-}"
      shift 2
      ;;
    --preset=*)
      PRESET="${1#--preset=}"
      shift
      ;;
    --out)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --out=*)
      OUTPUT_DIR="${1#--out=}"
      shift
      ;;
    --clean-smoke)
      CLEAN_SMOKE=1
      shift
      ;;
    --clean-core)
      CLEAN_CORE=1
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      LANES+=("$1")
      shift
      ;;
  esac
done

if [ "${#LANES[@]}" -eq 0 ]; then
  case "$PRESET" in
    quick)
      LANES=(smoke)
      ;;
    baseline)
      LANES=(smoke core-isolated unit appkit)
      ;;
    full)
      LANES=(smoke core-isolated unit appkit full)
      ;;
    *)
      echo "Unknown preset: $PRESET" >&2
      usage >&2
      exit 64
      ;;
  esac
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$OUTPUT_DIR/$STAMP.md"
TSV_REPORT="$OUTPUT_DIR/$STAMP.tsv"

{
  echo "# Local Loop Measurement"
  echo ""
  echo "- Timestamp: \`$STAMP\`"
  echo "- Preset: \`$PRESET\`"
  echo "- Lanes: \`${LANES[*]}\`"
  echo "- Output directory: \`$OUTPUT_DIR\`"
  echo ""
  echo "| Lane | Exit | Elapsed | Summary | Wrapper log | Test log |"
  echo "| --- | ---: | ---: | --- | --- | --- |"
} > "$REPORT"

printf "timestamp\tpreset\tlane\texit\telapsed_seconds\tsummary\twrapper_log\ttest_log\n" > "$TSV_REPORT"

failed_lanes=0

run_lane() {
  local lane="$1"
  local wrapper_log="$OUTPUT_DIR/$STAMP.$lane.wrapper.log"
  local test_log="$OUTPUT_DIR/$STAMP.$lane.test.log"
  local start_seconds
  local elapsed_seconds
  local exit_code
  local summary_line

  echo "==> Measuring lane: $lane"
  start_seconds="$(date +%s)"

  set +e
  if [ "$lane" = "smoke" ] && [ "$CLEAN_SMOKE" = "1" ]; then
    KEYPATH_ISOLATED_SMOKE_CLEAN=1 \
      KEYPATH_TEST_LOG="$test_log" \
      "$SCRIPT_DIR/test-lane.sh" "$lane" 2>&1 | tee "$wrapper_log"
  elif [ "$lane" = "core-isolated" ] && [ "$CLEAN_CORE" = "1" ]; then
    KEYPATH_ISOLATED_CORE_CLEAN=1 \
      KEYPATH_TEST_LOG="$test_log" \
      "$SCRIPT_DIR/test-lane.sh" "$lane" 2>&1 | tee "$wrapper_log"
  else
    KEYPATH_TEST_LOG="$test_log" \
      "$SCRIPT_DIR/test-lane.sh" "$lane" 2>&1 | tee "$wrapper_log"
  fi
  exit_code="${PIPESTATUS[0]}"
  set -e

  elapsed_seconds="$(( $(date +%s) - start_seconds ))"
  summary_line="$(awk '/Runner summary:|Isolated smoke summary:|Isolated Core summary:/ { line=$0 } END { print line }' "$wrapper_log")"
  if [ -z "$summary_line" ]; then
    summary_line="no summary line found"
  fi

  {
    echo "| \`$lane\` | \`$exit_code\` | \`${elapsed_seconds}s\` | \`$summary_line\` | \`$wrapper_log\` | \`$test_log\` |"
  } >> "$REPORT"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$STAMP" \
    "$PRESET" \
    "$lane" \
    "$exit_code" \
    "$elapsed_seconds" \
    "$summary_line" \
    "$wrapper_log" \
    "$test_log" >> "$TSV_REPORT"

  if [ "$exit_code" -ne 0 ]; then
    failed_lanes=$((failed_lanes + 1))
  fi
}

for lane in "${LANES[@]}"; do
  run_lane "$lane"
done

ln -sfn "$REPORT" "$OUTPUT_DIR/latest.md"
ln -sfn "$TSV_REPORT" "$OUTPUT_DIR/latest.tsv"

echo ""
echo "Report: $REPORT"
echo "TSV: $TSV_REPORT"
echo "Latest: $OUTPUT_DIR/latest.md"
echo "Latest TSV: $OUTPUT_DIR/latest.tsv"

if [ "$failed_lanes" -ne 0 ]; then
  echo "Local loop measurement completed with $failed_lanes failing lane(s)." >&2
  exit 1
fi

echo "Local loop measurement completed successfully."
