#!/bin/bash
# helpers.sh — Shared test harness for Peekaboo UI automation tests
#
# Provides: test lifecycle, Peekaboo wrappers with retries, app lifecycle management.
# All pb_* functions target --app KeyPath.

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

# ── State ──────────────────────────────────────────────────────────────────────
_SUITE_NAME=""
_SUITE_PASSED=0
_SUITE_FAILED=0
_SUITE_SKIPPED=0
_TEST_NAME=""
_TEST_START=""

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Logging ────────────────────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
}

log_debug() {
    if [[ "${UI_TEST_DEBUG:-0}" == "1" ]]; then
        echo -e "[DEBUG] $*"
    fi
}

# ── Test Lifecycle ─────────────────────────────────────────────────────────────

begin_suite() {
    _SUITE_NAME="$1"
    _SUITE_PASSED=0
    _SUITE_FAILED=0
    _SUITE_SKIPPED=0
    echo ""
    echo -e "${BOLD}━━━ Suite: $_SUITE_NAME ━━━${NC}"
    echo ""
}

begin_test() {
    _TEST_NAME="$1"
    _TEST_START=$(date +%s)
    log_info "Testing: $_TEST_NAME"
}

pass_test() {
    local elapsed=$(( $(date +%s) - _TEST_START ))
    log_pass "$_TEST_NAME (${elapsed}s)"
    ((_SUITE_PASSED++))
}

fail_test() {
    local reason="${1:-}"
    local elapsed=$(( $(date +%s) - _TEST_START ))
    if [[ -n "$reason" ]]; then
        log_fail "$_TEST_NAME (${elapsed}s): $reason"
    else
        log_fail "$_TEST_NAME (${elapsed}s)"
    fi
    ((_SUITE_FAILED++))

    # Auto-screenshot on failure
    pb_screenshot "FAIL-${_TEST_NAME}" 2>/dev/null || true
}

skip_test() {
    local reason="${1:-}"
    if [[ -n "$reason" ]]; then
        log_skip "$_TEST_NAME: $reason"
    else
        log_skip "$_TEST_NAME"
    fi
    ((_SUITE_SKIPPED++))
}

end_suite() {
    local total=$(( _SUITE_PASSED + _SUITE_FAILED + _SUITE_SKIPPED ))
    echo ""
    echo -e "${BOLD}── $_SUITE_NAME Results ──${NC}"
    echo -e "  ${GREEN}Passed:${NC}  $_SUITE_PASSED"
    echo -e "  ${RED}Failed:${NC}  $_SUITE_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $_SUITE_SKIPPED"
    echo -e "  Total:   $total"
    echo ""

    # Return non-zero if any failures
    [[ $_SUITE_FAILED -eq 0 ]]
}

# ── Peekaboo Wrappers ─────────────────────────────────────────────────────────
# All commands target --app KeyPath with built-in retries and logging.

_pb_retry() {
    # Retry a peekaboo command up to N times with a delay between attempts.
    local max_attempts="${1:-3}"
    local delay="${2:-1}"
    shift 2
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if "$@" 2>/dev/null; then
            return 0
        fi
        log_debug "Attempt $attempt/$max_attempts failed: $*"
        sleep "$delay"
        ((attempt++))
    done
    return 1
}

pb_click() {
    # Click element by accessibility identifier.
    local identifier="$1"
    log_debug "pb_click: $identifier"
    _pb_retry 3 1 peekaboo click --app KeyPath --id "$identifier"
}

pb_click_label() {
    # Click element by visible label text.
    local label="$1"
    log_debug "pb_click_label: $label"
    _pb_retry 3 1 peekaboo click --app KeyPath --label "$label"
}

pb_type() {
    # Type text into the focused field.
    local text="$1"
    log_debug "pb_type: $text"
    peekaboo type --app KeyPath "$text"
}

pb_screenshot() {
    # Save screenshot to results directory.
    local description="$1"
    local sanitized
    sanitized=$(echo "$description" | tr ' /' '-' | tr -cd '[:alnum:]-_')
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local filename="${_SUITE_NAME:-unknown}-${sanitized}-${timestamp}.png"
    local filepath="$RESULTS_DIR/$filename"

    log_debug "pb_screenshot: $filepath"
    peekaboo see --app KeyPath --output "$filepath" "screenshot" 2>/dev/null || true
    if [[ -f "$filepath" ]]; then
        log_info "Screenshot saved: $filename"
    fi
}

pb_assert_exists() {
    # Assert element with accessibility identifier is visible.
    local identifier="$1"
    local max_wait="${2:-5}"
    log_debug "pb_assert_exists: $identifier (timeout: ${max_wait}s)"

    if pb_wait_for "$identifier" "$max_wait"; then
        return 0
    else
        return 1
    fi
}

pb_assert_not_exists() {
    # Assert element with accessibility identifier is NOT visible.
    local identifier="$1"
    log_debug "pb_assert_not_exists: $identifier"

    # Try to find it — if peekaboo click succeeds, the element exists (bad).
    if peekaboo click --app KeyPath --id "$identifier" --dry-run 2>/dev/null; then
        return 1  # Element found, assertion fails
    else
        return 0  # Element not found, assertion passes
    fi
}

pb_wait_for() {
    # Wait for element to appear, polling every second.
    local identifier="$1"
    local timeout="${2:-10}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if peekaboo click --app KeyPath --id "$identifier" --dry-run 2>/dev/null; then
            log_debug "pb_wait_for: $identifier found after ${elapsed}s"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    log_debug "pb_wait_for: $identifier NOT found after ${timeout}s"
    return 1
}

pb_scroll() {
    # Scroll in a direction.
    local direction="$1"
    local amount="${2:-3}"
    log_debug "pb_scroll: $direction ($amount)"
    peekaboo scroll --app KeyPath --direction "$direction" --amount "$amount" 2>/dev/null
}

pb_hotkey() {
    # Trigger a keyboard shortcut.
    # Usage: pb_hotkey "cmd+opt+k"
    local shortcut="$1"
    log_debug "pb_hotkey: $shortcut"
    peekaboo hotkey "$shortcut"
}

pb_see() {
    # Ask Peekaboo to analyze what's visible, returns AI description.
    local prompt="${1:-What is visible on screen?}"
    log_debug "pb_see: $prompt"
    peekaboo see --app KeyPath "$prompt" 2>/dev/null
}

# ── App Lifecycle ──────────────────────────────────────────────────────────────

ensure_app_running() {
    # Launch KeyPath in accessibility test mode if not already running.
    if ! pgrep -x "KeyPath" > /dev/null 2>&1; then
        log_info "Launching KeyPath in test mode..."
        KEYPATH_ACCESSIBILITY_TEST_MODE=1 open -a KeyPath
        sleep 3
    else
        log_info "KeyPath is already running"
    fi
    # Wait for the app to be responsive
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        if peekaboo see --app KeyPath "Is the app visible?" >/dev/null 2>&1; then
            log_info "KeyPath is responsive"
            return 0
        fi
        sleep 1
        ((attempts++))
    done
    log_fail "KeyPath did not become responsive"
    return 1
}

quit_app() {
    # Gracefully quit KeyPath.
    log_info "Quitting KeyPath..."
    osascript -e 'tell application "KeyPath" to quit' 2>/dev/null || true
    sleep 2
    # Force kill if still running
    if pgrep -x "KeyPath" > /dev/null 2>&1; then
        killall "KeyPath" 2>/dev/null || true
        sleep 1
    fi
}

restart_app() {
    # Quit and relaunch KeyPath (clears stale AX state).
    quit_app
    sleep 1
    ensure_app_running
}

# ── Utility ────────────────────────────────────────────────────────────────────

wait_seconds() {
    # Sleep with a log message.
    local seconds="$1"
    local reason="${2:-waiting}"
    log_debug "Waiting ${seconds}s ($reason)"
    sleep "$seconds"
}

# Export RESULTS_DIR for suites
export RESULTS_DIR
