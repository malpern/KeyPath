#!/bin/bash
set -euo pipefail

# KeyPath Safe Test Runner
# - Runs both XCTest and Swift Testing tests via `swift test`
# - Skips CGEvent taps in code under test to prevent hangs
# - Adds a watchdog timeout so CI never freezes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-240}
ALLOW_RUNNER_CRASH_SUCCESS=${KEYPATH_ALLOW_TEST_RUNNER_CRASH_SUCCESS:-0}
ALLOW_NONZERO_TEST_SUCCESS=${KEYPATH_ALLOW_NONZERO_TEST_SUCCESS:-0}
TEST_FILTER=${TEST_FILTER:-}
TEST_SKIP=${TEST_SKIP:-}
SWIFT_TEST_ARGS=${SWIFT_TEST_ARGS:-}

echo "🧪 Running tests via swift test with safety guards..."

absolute_dir() {
  local path="$1"
  case "$path" in
    /*) ;;
    *) path="$PROJECT_DIR/$path" ;;
  esac
  mkdir -p "$path"
  (cd "$path" && pwd -P)
}

log_size_bytes() {
  local path="${1:-}"
  if [ -n "$path" ] && [ -f "$path" ]; then
    wc -c < "$path" | tr -d '[:space:]'
  else
    echo "0"
  fi
}

count_log_pattern() {
  local pattern="$1"
  local path="${2:-}"
  if [ -n "$path" ] && [ -f "$path" ]; then
    grep -cE "$pattern" "$path" 2>/dev/null || true
  else
    echo "0"
  fi
}

format_duration() {
  local value="${1:-not-run}"
  if [ "$value" = "not-run" ]; then
    echo "not-run"
  else
    echo "${value}s"
  fi
}

print_run_summary() {
  local exit_code="${1:-unknown}"
  local now_seconds
  local total_duration
  local log_size
  local build_log_size
  local build_duration
  local test_duration
  local build_log_swift_warning_count
  local test_log_swift_warning_count
  local test_log_app_warning_count
  local test_log_app_error_count
  local filter_value
  local skip_value

  if [ "$SUMMARY_PRINTED" = "1" ]; then
    return 0
  fi

  now_seconds="$(date +%s)"
  total_duration=$((now_seconds - RUNNER_START_SECONDS))
  log_size="$(log_size_bytes "${LOG:-}")"
  build_log_size="$(log_size_bytes "${BUILD_LOG:-}")"
  build_duration="$(format_duration "$BUILD_DURATION_SECONDS")"
  test_duration="$(format_duration "$TEST_DURATION_SECONDS")"
  build_log_swift_warning_count="$(count_log_pattern "warning:" "${BUILD_LOG:-}")"
  test_log_swift_warning_count="$(count_log_pattern "warning:" "${LOG:-}")"
  test_log_app_warning_count="$(count_log_pattern "\\[WARN\\]" "${LOG:-}")"
  test_log_app_error_count="$(count_log_pattern "\\[ERROR\\]" "${LOG:-}")"
  filter_value="${TEST_FILTER:-none}"
  skip_value="${TEST_SKIP:-none}"

  echo "📊 Runner summary: lane=${TEST_LANE} exit=${exit_code} prebuild=${TEST_PREBUILD} disable_xctest=${TEST_DISABLE_XCTEST} reset_module_cache=${TEST_RESET_MODULE_CACHE} build=${build_duration} test=${test_duration} total=${total_duration}s build_log=${build_log_size} bytes build_log_swift_warnings=${build_log_swift_warning_count} log=${log_size} bytes test_log_swift_warnings=${test_log_swift_warning_count} test_log_app_warnings=${test_log_app_warning_count} test_log_app_errors=${test_log_app_error_count}"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### KeyPath Safe Test Runner"
      echo ""
      echo "| Metric | Value |"
      echo "| --- | --- |"
      echo "| Lane | \`${TEST_LANE}\` |"
      echo "| Filter | \`${filter_value}\` |"
      echo "| Skip | \`${skip_value}\` |"
      echo "| Prebuild | \`${TEST_PREBUILD}\` |"
      echo "| Disable XCTest | \`${TEST_DISABLE_XCTEST}\` |"
      echo "| Reset module cache | \`${TEST_RESET_MODULE_CACHE}\` |"
      echo "| Exit code | \`${exit_code}\` |"
      echo "| Build duration | \`${build_duration}\` |"
      echo "| Test duration | \`${test_duration}\` |"
      echo "| Total duration | \`${total_duration}s\` |"
      echo "| Build log size | \`${build_log_size} bytes\` |"
      echo "| Build log Swift warnings | \`${build_log_swift_warning_count}\` |"
      echo "| Log size | \`${log_size} bytes\` |"
      echo "| Test log Swift warnings | \`${test_log_swift_warning_count}\` |"
      echo "| Test log app warnings | \`${test_log_app_warning_count}\` |"
      echo "| Test log app errors | \`${test_log_app_error_count}\` |"
      if [ -n "${BUILD_LOG:-}" ]; then
        echo "| Build log path | \`${BUILD_LOG}\` |"
      fi
      if [ -n "${LOG:-}" ]; then
        echo "| Log path | \`${LOG}\` |"
      fi
      echo ""
    } >> "$GITHUB_STEP_SUMMARY"
  fi

  SUMMARY_PRINTED=1
}

kill_process_tree() {
  local pid="${1:-}"
  local child

  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi

  while read -r child; do
    [ -z "$child" ] && continue
    kill_process_tree "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  kill -KILL "$pid" 2>/dev/null || true
}

terminate_process_tree() {
  local pid="${1:-}"
  kill_process_tree "$pid"
  if [ -n "$pid" ]; then
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup_orphaned_xctest() {
  [ -z "${SCRATCH_PATH:-}" ] && return 0

  while read -r pid; do
    [ -z "$pid" ] && continue
    local command_line
    command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command_line" in
      *"$SCRATCH_PATH"*) ;;
      *) continue ;;
    esac
    echo "🧹 Cleaning up orphaned KeyPathPackageTests.xctest process (pid=$pid)"
    terminate_process_tree "$pid"
  done < <(pgrep -f "KeyPathPackageTests\\.xctest" 2>/dev/null || true)
}

cleanup() {
  local exit_code=$?

  [ "${CLEANUP_ARMED:-1}" = "1" ] || return "$exit_code"

  if [ -n "${WATCHDOG_PID:-}" ] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    terminate_process_tree "$WATCHDOG_PID"
  fi

  if [ -n "${TEST_PID:-}" ] && kill -0 "$TEST_PID" 2>/dev/null; then
    terminate_process_tree "$TEST_PID"
  fi

  cleanup_orphaned_xctest
  [ -n "${EXIT_FILE:-}" ] && rm -f "$EXIT_FILE"
  [ -n "${TIMEOUT_FILE:-}" ] && rm -f "$TIMEOUT_FILE"

  return "$exit_code"
}

on_signal() {
  local signal="$1"
  echo "⚠️  Received $signal; cleaning up test processes..."
  cleanup
  print_run_summary 130
  exit 130
}

trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP

# 1) Environment for test-safe code paths
export SWIFT_TEST=1
export SKIP_EVENT_TAP_TESTS=1
export CI_ENVIRONMENT=${CI_ENVIRONMENT:-false}
export NSUnbufferedIO=YES

# Keep default test output focused. AppLogger uses numeric levels:
# trace=0, debug=1, info=2, warn=3, error=4.
if [ "${KEYPATH_TEST_VERBOSE_LOGS:-0}" = "1" ]; then
    export KEYPATH_LOG_LEVEL=${KEYPATH_LOG_LEVEL:-1}
else
    export KEYPATH_LOG_LEVEL=${KEYPATH_LOG_LEVEL:-3}
fi

# Optional: Enable sudo mode for fully autonomous privileged operations
# Set KEYPATH_USE_SUDO=1 to use sudo instead of osascript admin prompts
# Auto-detect if sudoers are configured and enable automatically
#
# IMPORTANT: In CI we must keep tests hermetic and avoid privileged system modifications.
# CI-safe tests should exercise "test mode" code paths (TestEnvironment.shouldSkipAdminOperations == true).
if [ "${CI_ENVIRONMENT}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    export KEYPATH_USE_SUDO=${KEYPATH_USE_SUDO:-0}
    echo "🔒 CI mode - forcing KEYPATH_USE_SUDO=$KEYPATH_USE_SUDO"
elif [ -z "${KEYPATH_USE_SUDO:-}" ]; then
    # Check if sudo -n works (NOPASSWD configured)
    if sudo -n launchctl list com.keypath.kanata >/dev/null 2>&1 || \
       sudo -n true >/dev/null 2>&1; then
        export KEYPATH_USE_SUDO=1
        echo "🔐 Auto-detected sudoers config - enabling KEYPATH_USE_SUDO=1"
    else
        export KEYPATH_USE_SUDO=0
    fi
else
    export KEYPATH_USE_SUDO=${KEYPATH_USE_SUDO}
fi

echo "⏱️  Timeout: ${TIMEOUT_SECONDS}s"
echo "🛣️  Test lane: $TEST_LANE"
if [ -n "$TEST_FILTER" ]; then
    echo "🔎 Test filter: $TEST_FILTER"
fi
if [ -n "$TEST_SKIP" ]; then
    echo "⏭️  Test skip: $TEST_SKIP"
fi
echo "🏗️  Test prebuild: $TEST_PREBUILD | disable XCTest: $TEST_DISABLE_XCTEST | reset module cache: $TEST_RESET_MODULE_CACHE"
echo "🧪 SWIFT_TEST=$SWIFT_TEST | SKIP_EVENT_TAP_TESTS=$SKIP_EVENT_TAP_TESTS"
declare -a TEST_SELECTOR_ARGS=()
if [ -n "$TEST_FILTER" ]; then
    TEST_SELECTOR_ARGS+=(--filter "$TEST_FILTER")
fi
if [ -n "$TEST_SKIP" ]; then
    TEST_SELECTOR_ARGS+=(--skip "$TEST_SKIP")
fi
declare -a EXTRA_TEST_ARGS=()
if [ -n "$SWIFT_TEST_ARGS" ]; then
    # shellcheck disable=SC2206
    EXTRA_TEST_ARGS=($SWIFT_TEST_ARGS)
fi
if [ "${#TEST_SELECTOR_ARGS[@]}" -gt 0 ] || [ "${#EXTRA_TEST_ARGS[@]}" -gt 0 ]; then
    echo "🎯 Test selector args: ${TEST_SELECTOR_ARGS[*]:-(none)}"
    echo "⚙️  Extra swift test args: ${EXTRA_TEST_ARGS[*]:-(none)}"
else
    echo "🎯 Test selector args: (full suite)"
fi
if [ "$ALLOW_RUNNER_CRASH_SUCCESS" = "1" ]; then
    echo "⚠️  KEYPATH_ALLOW_TEST_RUNNER_CRASH_SUCCESS=1 (signal crashes can pass only with zero parsed failures)"
fi
if [ "$ALLOW_NONZERO_TEST_SUCCESS" = "1" ]; then
    echo "⚠️  KEYPATH_ALLOW_NONZERO_TEST_SUCCESS=1 (non-zero exits with parsed passes can pass)"
fi
if [ "$KEYPATH_USE_SUDO" = "1" ]; then
    echo "🔐 KEYPATH_USE_SUDO=1 (privileged ops via sudo, no prompts)"
fi

append_runner_crash_summary() {
    local title="$1"
    local details="$2"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### $title"
            echo ""
            echo "- Parsed passes: \`$PASS_COUNT\`"
            echo "- Parsed failures: \`$FAIL_COUNT\`"
            echo "- Exit code: \`$EXIT_CODE\`"
            echo "- Detail: $details"
            echo ""
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}

# 0) Isolated build/test dirs and HOME to avoid parallel-agent collisions
# In CI, reuse the default .build/ to avoid relinking the CLI executable
# (keypath depends on KeyPathAppKit → SwiftUI, which can fail to link from a
# fresh scratch path on Xcode 16.4 due to SwiftUICore client restrictions).
if [ "${CI_ENVIRONMENT}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    SCRATCH_PATH=${SCRATCH_PATH:-"$PROJECT_DIR/.build"}
else
    SCRATCH_PATH=${SCRATCH_PATH:-"$PROJECT_DIR/.build-ci"}
fi
export HOME=${TEST_HOME:-$(mktemp -d 2>/dev/null || mktemp -d -t keypath-tests)}
SCRATCH_PATH="$(absolute_dir "$SCRATCH_PATH")"
MODULE_CACHE="$SCRATCH_PATH/ModuleCache.noindex"
if [ "$TEST_RESET_MODULE_CACHE" = "1" ] && [ -d "$MODULE_CACHE" ]; then
  echo "🧹 Resetting generated module cache: $MODULE_CACHE"
  rm -rf "$MODULE_CACHE"
elif [ "$TEST_RESET_MODULE_CACHE" != "1" ]; then
  echo "♻️  Reusing generated module cache: $MODULE_CACHE"
fi
MODULE_CACHE="$(absolute_dir "$MODULE_CACHE")"
HOME="$(absolute_dir "$HOME")"
export CLANG_MODULECACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE"
MODULE_CACHE_FLAGS=(-Xcc "-fmodules-cache-path=$MODULE_CACHE")
SWIFT_TEST_ARGS=()
if [ -n "$TEST_FILTER" ]; then
  SWIFT_TEST_ARGS+=(--filter "$TEST_FILTER")
fi
if [ -n "$TEST_SKIP" ]; then
  SWIFT_TEST_ARGS+=(--skip "$TEST_SKIP")
fi
if [ "$TEST_DISABLE_XCTEST" = "1" ]; then
  SWIFT_TEST_ARGS+=(--disable-xctest)
fi
echo "📦 Scratch: $SCRATCH_PATH | HOME=$HOME"
echo "🗂️  Module cache: $MODULE_CACHE"
mkdir -p "$(dirname "$LOG")" "$(dirname "$BUILD_LOG")"
rm -f "$LOG" "$BUILD_LOG"

# 1) Build tests first (doesn't count against watchdog timeout)
echo "🔨 Building tests..."
BUILD_START_SECONDS="$(date +%s)"
set +e
if [ "$TEST_PREBUILD" = "0" ]; then
  echo "⏭️  Skipping separate swift build --build-tests step"
  BUILD_EXIT_CODE=0
else
  swift build --build-tests --scratch-path "$SCRATCH_PATH" "${MODULE_CACHE_FLAGS[@]}" 2>&1 | tee "$BUILD_LOG"
  BUILD_EXIT_CODE="${PIPESTATUS[0]}"
fi
set -e
BUILD_DURATION_SECONDS=$(($(date +%s) - BUILD_START_SECONDS))
if [ "$BUILD_EXIT_CODE" != "0" ]; then
  echo "❌ Test build failed (exit $BUILD_EXIT_CODE)"
  print_run_summary "$BUILD_EXIT_CODE"
  exit "$BUILD_EXIT_CODE"
fi

# 2) Run with watchdog
EXIT_FILE="$PROJECT_DIR/.xctest.exit.$$"
TIMEOUT_FILE="$PROJECT_DIR/.xctest.timeout.$$"

echo "🚀 Launching swift test..."
TEST_START_SECONDS="$(date +%s)"

(
  set +e
  set -o pipefail
  SWIFT_TEST_COMMAND=(swift test --skip-build --scratch-path "$SCRATCH_PATH" "${MODULE_CACHE_FLAGS[@]}")
  if [ "${#TEST_SELECTOR_ARGS[@]}" -gt 0 ]; then
    SWIFT_TEST_COMMAND+=("${TEST_SELECTOR_ARGS[@]}")
  fi
  if [ "${#EXTRA_TEST_ARGS[@]}" -gt 0 ]; then
    SWIFT_TEST_COMMAND+=("${EXTRA_TEST_ARGS[@]}")
  fi
  "${SWIFT_TEST_COMMAND[@]}" 2>&1 | tee "$LOG"
  echo $? > .xctest.exit
) &

TEST_PID=$!

# Watchdog
(
  SECS=0
  while kill -0 $TEST_PID 2>/dev/null; do
    sleep 1
    SECS=$((SECS+1))
    if [ $SECS -ge $TIMEOUT_SECONDS ]; then
      echo "⏰ Timeout after ${TIMEOUT_SECONDS}s. Killing tests (pid=$TEST_PID)."
      echo "1" > "$TIMEOUT_FILE"
      kill_process_tree "$TEST_PID"
      cleanup_orphaned_xctest
      echo "124" > "$EXIT_FILE"
      break
    fi
  done
) & WATCHDOG_PID=$!

wait $TEST_PID || true
EXIT_CODE=$(cat .xctest.exit 2>/dev/null || echo 1)
rm -f .xctest.exit
kill $WATCHDOG_PID 2>/dev/null || true
wait $WATCHDOG_PID 2>/dev/null || true

# 2) Summarize
# Count actual test failures vs passes (both XCTest and Swift Testing formats)
FAIL_COUNT=$(grep -cE "Test Case '.*' failed|Test .* failed after" "$LOG" 2>/dev/null || true)
FAIL_COUNT=${FAIL_COUNT:-0}
PASS_COUNT=$(grep -cE "Test Case '.*' passed|Test .* passed after" "$LOG" 2>/dev/null || true)
PASS_COUNT=${PASS_COUNT:-0}
IS_SIGNAL_CRASH=false
if [ "$EXIT_CODE" -gt 128 ] 2>/dev/null; then
  IS_SIGNAL_CRASH=true
fi
LOG_SIGNAL_CRASH_LINE=$(grep -aE "exited with unexpected signal code [0-9]+" "$LOG" 2>/dev/null | tail -n 1 || true)
LOG_SIGNAL_CRASH=false
if [ -n "$LOG_SIGNAL_CRASH_LINE" ]; then
  LOG_SIGNAL_CRASH=true
fi

if [ "$EXIT_CODE" = "0" ]; then
  echo "✅ All tests passed ($PASS_COUNT passed)"
  print_run_summary "$EXIT_CODE"
  exit 0
fi

if [ "$EXIT_CODE" = "124" ]; then
  echo "⚠️  Tests timed out; see $LOG"
  print_run_summary "$EXIT_CODE"
  exit 124
fi

# Signal crash (SIGTRAP=133, SIGABRT=134, etc.) — check if tests actually failed
# or if the runner just crashed during teardown / a SwiftUI animation call in CI
if [ "$IS_SIGNAL_CRASH" = true ]; then
  SIGNAL_NUM=$((EXIT_CODE - 128))
  echo "⚠️  Test runner crashed with signal $SIGNAL_NUM (exit $EXIT_CODE)"
  echo "   Passed: $PASS_COUNT | Failed: $FAIL_COUNT"

  if [ "$ALLOW_RUNNER_CRASH_SUCCESS" = "1" ] && [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::warning::Allowed test runner signal crash after $PASS_COUNT parsed passes and 0 parsed failures"
    fi
    append_runner_crash_summary "Allowed Test Runner Signal Crash" "signal $SIGNAL_NUM"
    echo "✅ Tests passed (ignoring allowed runner crash — $PASS_COUNT passed, 0 parsed failures)"
    exit 0
  fi

  echo "❌ Treating test runner signal crash as failure"
  exit "$EXIT_CODE"
fi

# SwiftPM can wrap an XCTest SIGABRT as exit 1 while logging the underlying signal.
if [ "$LOG_SIGNAL_CRASH" = true ]; then
  echo "⚠️  Test runner reported a signal crash: $LOG_SIGNAL_CRASH_LINE"
  echo "   Exit: $EXIT_CODE | Passed: $PASS_COUNT | Failed: $FAIL_COUNT"

  if [ "$ALLOW_RUNNER_CRASH_SUCCESS" = "1" ] && [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::warning::Allowed SwiftPM-wrapped test runner signal crash after $PASS_COUNT parsed passes and 0 parsed failures"
    fi
    append_runner_crash_summary "Allowed SwiftPM-Wrapped Test Runner Signal Crash" "$LOG_SIGNAL_CRASH_LINE"
    echo "✅ Tests passed (ignoring allowed runner crash — $PASS_COUNT passed, 0 parsed failures)"
    exit 0
  fi

  echo "❌ Treating test runner signal crash as failure"
  exit "$EXIT_CODE"
fi

# Check for real test failures
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "❌ $FAIL_COUNT test(s) failed ($PASS_COUNT passed)"
  grep -E "Test Case '.*' failed|Test .* failed after" "$LOG" || true
  print_run_summary "$EXIT_CODE"
  exit 1
fi

# Non-zero exit but no failures found — check for any passing output
if [ "$ALLOW_NONZERO_TEST_SUCCESS" = "1" ] && [ "$PASS_COUNT" -gt 0 ]; then
  echo "✅ Tests passed (ignoring allowed runner exit code $EXIT_CODE — $PASS_COUNT passed)"
  exit 0
fi

if [ "$PASS_COUNT" -gt 0 ]; then
  echo "❌ Test run failed (exit $EXIT_CODE despite $PASS_COUNT parsed passes)"
else
  echo "❌ Test run failed (exit $EXIT_CODE, no test output found)"
fi
exit $EXIT_CODE
