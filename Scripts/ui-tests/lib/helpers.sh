#!/bin/bash
# helpers.sh — Shared test harness for Peekaboo UI automation tests
#
# Provides: test lifecycle, Peekaboo wrappers with retries, app lifecycle management.
# All pb_* functions target --app KeyPath.
#
# Requires: Peekaboo 3.x (brew install steipete/tap/peekaboo)

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
    _SUITE_PASSED=$(( _SUITE_PASSED + 1 ))
}

fail_test() {
    local reason="${1:-}"
    local elapsed=$(( $(date +%s) - _TEST_START ))
    if [[ -n "$reason" ]]; then
        log_fail "$_TEST_NAME (${elapsed}s): $reason"
    else
        log_fail "$_TEST_NAME (${elapsed}s)"
    fi
    _SUITE_FAILED=$(( _SUITE_FAILED + 1 ))

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
    _SUITE_SKIPPED=$(( _SUITE_SKIPPED + 1 ))
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
# All commands target --app KeyPath.
# Peekaboo 3.x API:
#   click [query]       - click by text/accessibility-id fuzzy match
#   click --on <id>     - click by Peekaboo snapshot element ID (e.g., B1, elem_3)
#   see --json          - capture UI element map (returns accessibility identifiers)
#   image --path <path> - save screenshot
#   hotkey "key1,key2"  - press keyboard shortcut (comma-separated)
#   type "text"         - type text
#   scroll              - scroll with --direction and --amount

pb_click() {
    # Click element by accessibility identifier (uses query-based fuzzy matching).
    # Peekaboo's click [query] searches text, labels, AND accessibility identifiers.
    local identifier="$1"
    log_debug "pb_click: $identifier"
    _pb_activate_app
    peekaboo click "$identifier" --app KeyPath >/dev/null 2>&1
}

pb_click_label() {
    # Click element by visible label text (same mechanism as pb_click).
    local label="$1"
    log_debug "pb_click_label: $label"
    _pb_activate_app
    peekaboo click "$label" --app KeyPath >/dev/null 2>&1
}

pb_type() {
    # Type text into the focused field.
    local text="$1"
    log_debug "pb_type: $text"
    peekaboo type "$text" --app KeyPath --profile linear --delay 20 >/dev/null 2>&1
}

pb_screenshot() {
    # Save screenshot to results directory using peekaboo image.
    local description="$1"
    local sanitized
    sanitized=$(echo "$description" | tr ' /' '-' | tr -cd '[:alnum:]-_')
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local filename="${_SUITE_NAME:-unknown}-${sanitized}-${timestamp}.png"
    local filepath="$RESULTS_DIR/$filename"

    log_debug "pb_screenshot: $filepath"
    _pb_activate_app
    peekaboo image --app KeyPath --path "$filepath" 2>/dev/null || true
    if [[ -f "$filepath" ]]; then
        log_info "Screenshot saved: $filename"
    fi
}

# ── Element Existence Checks ─────────────────────────────────────────────────
# These use `peekaboo see --json` to check for accessibility identifiers
# WITHOUT clicking or otherwise interacting with the element.

_pb_activate_app() {
    # Ensure KeyPath is the frontmost app so its AX tree is accessible.
    # The overlay window requires KeyPath to be active for AX enumeration
    # (even with .ignoresCycle removed, floating windows need activation).
    osascript -e 'tell application "KeyPath" to activate' 2>/dev/null || true
    sleep 0.3
}

_pb_element_exists() {
    # Internal: check if accessibility identifier exists in current UI snapshot.
    # Returns 0 if found, 1 if not found.
    # Pipes directly from peekaboo to python to avoid bash variable corruption.
    local identifier="$1"

    # Activate KeyPath so its AX tree is discoverable
    _pb_activate_app

    # Query all KeyPath windows — pipe directly to avoid bash variable mangling
    peekaboo see --app KeyPath --json 2>/dev/null | python3 -c "
import json, sys
identifier = sys.argv[1]
raw = sys.stdin.buffer.read().decode('utf-8', errors='replace')
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(1)
elements = data.get('data', {}).get('ui_elements', [])
found = any(e.get('identifier') == identifier for e in elements)
sys.exit(0 if found else 1)
" "$identifier" 2>/dev/null
}

pb_assert_exists() {
    # Assert element with accessibility identifier is visible (non-destructive).
    local identifier="$1"
    local max_wait="${2:-5}"
    log_debug "pb_assert_exists: $identifier (timeout: ${max_wait}s)"
    pb_wait_for "$identifier" "$max_wait"
}

pb_assert_not_exists() {
    # Assert element with accessibility identifier is NOT visible.
    local identifier="$1"
    log_debug "pb_assert_not_exists: $identifier"
    if _pb_element_exists "$identifier"; then
        return 1  # Element found — assertion fails
    else
        return 0  # Element not found — assertion passes
    fi
}

pb_wait_for() {
    # Wait for element to appear, polling via see --json.
    local identifier="$1"
    local timeout="${2:-10}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if _pb_element_exists "$identifier"; then
            log_debug "pb_wait_for: $identifier found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$(( elapsed + 1 ))
    done

    log_debug "pb_wait_for: $identifier NOT found after ${timeout}s"
    return 1
}

pb_scroll() {
    # Scroll in a direction.
    local direction="$1"
    local amount="${2:-3}"
    log_debug "pb_scroll: $direction ($amount)"
    peekaboo scroll --direction "$direction" --amount "$amount" --app KeyPath >/dev/null 2>&1
}

pb_hotkey() {
    # Trigger a keyboard shortcut.
    # Usage: pb_hotkey "cmd+w" or pb_hotkey "cmd+alt+k"
    # Converts + separator to , and opt→alt for Peekaboo 3.x format.
    local shortcut="$1"
    log_debug "pb_hotkey: $shortcut"

    # Special case: Cmd+, (open settings) — comma key has no name in Peekaboo,
    # so use menu click instead.
    if [[ "$shortcut" == "cmd+," ]]; then
        peekaboo menu click --app KeyPath --path "KeyPath > Settings…" >/dev/null 2>&1
        return
    fi

    # Convert format: opt→alt, +→, (comma separator for Peekaboo)
    local converted
    converted=$(echo "$shortcut" | sed 's/opt/alt/g; s/+/,/g')
    peekaboo hotkey "$converted" --app KeyPath >/dev/null 2>&1
}

pb_see() {
    # Ask Peekaboo to analyze what's visible, returns AI description.
    local prompt="${1:-What is visible on screen?}"
    log_debug "pb_see: $prompt"
    peekaboo see --app KeyPath --analyze "$prompt" 2>/dev/null
}

# ── App Lifecycle ──────────────────────────────────────────────────────────────

ensure_app_running() {
    # Launch KeyPath in accessibility test mode if not already running.
    if ! pgrep -x "KeyPath" > /dev/null 2>&1; then
        log_info "Launching KeyPath in test mode..."
        # Set accessibility test mode via UserDefaults (persistent setting).
        # Note: We no longer set launchctl setenv because it leaks into all processes
        # if cleanup doesn't run (e.g., test aborted). The UserDefaults pref is sufficient
        # and the app reads it at window creation time.
        defaults write com.keypath.KeyPath "KeyPath.Testing.AccessibilityTestMode" -bool true
        open -a KeyPath
        sleep 5
    else
        log_info "KeyPath is already running"
    fi

    # If the wizard auto-launched (helper XPC check failed on fresh boot),
    # dismiss it so the overlay is accessible for non-wizard test suites.
    _dismiss_wizard_if_present

    # Wait for the overlay window to appear in Peekaboo
    local attempts=0
    while [[ $attempts -lt 15 ]]; do
        if _pb_element_exists "keyboard-overlay" 2>/dev/null; then
            log_info "KeyPath overlay is visible"
            # Health gate: wait for validation to finish and verify system is green
            _require_system_healthy
            return 0
        fi
        sleep 1
        attempts=$(( attempts + 1 ))
    done

    # Overlay not detected — try showing it via hotkey
    log_info "Overlay not detected, trying Cmd+Alt+K hotkey..."
    peekaboo hotkey "cmd,alt,k" >/dev/null 2>&1 || true
    sleep 2

    # One more check
    if _pb_element_exists "keyboard-overlay" 2>/dev/null; then
        log_info "KeyPath overlay is now visible"
        _require_system_healthy
        return 0
    fi

    log_info "Warning: KeyPath overlay may not be accessible to Peekaboo"
    return 0
}

_dismiss_wizard_if_present() {
    # The wizard auto-launches ~1s after startup if the helper XPC check
    # fails. It opens on top of the overlay and blocks test interaction.
    # Close it via the close button or Cmd+W fallback.
    local wait_attempts=0
    while [[ $wait_attempts -lt 3 ]]; do
        if _pb_element_exists "wizard-close-button" 2>/dev/null; then
            log_info "Wizard detected — dismissing..."
            peekaboo click "wizard-close-button" --app KeyPath --wait-for 3000 >/dev/null 2>&1 \
                || peekaboo hotkey "cmd,w" --app KeyPath >/dev/null 2>&1 || true
            sleep 1
            log_info "Wizard dismissed"
            return 0
        fi
        sleep 1
        wait_attempts=$(( wait_attempts + 1 ))
    done
}

_require_system_healthy() {
    # Wait for KeyPath's startup health check to finish, then verify the
    # system is green. The health indicator transitions through:
    #   .checking → .healthy ("Ready", briefly) → .dismissed   (green)
    #   .checking → .unhealthy("N Issues")                     (not green)
    #
    # If the system has issues, abort the entire test run with a clear
    # message — tests cannot pass against a broken system.

    log_info "Waiting for health check to complete..."

    # Give the health check time to finish (checking → healthy/unhealthy).
    # Poll for up to 20 seconds: either the indicator shows issues, or
    # the health indicator disappears (dismissed = healthy).
    local elapsed=0
    while [[ $elapsed -lt 20 ]]; do
        if _pb_element_exists "overlay-health-indicator" 2>/dev/null; then
            # Check the label to determine state
            local label
            label=$(_pb_get_label "overlay-health-indicator" 2>/dev/null) || label=""

            # Unhealthy: label contains "issue" (e.g., "System has 3 issues. Click to fix.")
            if echo "$label" | grep -qi "issue"; then
                echo ""
                echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${RED}${BOLD}  SYSTEM NOT READY — Tests cannot proceed${NC}"
                echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                echo -e "  KeyPath is reporting: ${YELLOW}${label}${NC}"
                echo ""
                echo -e "  Please fix all issues before running UI tests:"
                echo -e "    1. Click the orange health indicator in the overlay"
                echo -e "    2. Follow the wizard to resolve all issues"
                echo -e "    3. Verify the overlay shows a green ${GREEN}Ready${NC} checkmark"
                echo -e "    4. Re-run the tests"
                echo ""
                echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                exit 2
            fi

            # Still checking — wait for it to finish
            sleep 1
            elapsed=$(( elapsed + 1 ))
            continue
        fi

        # Health indicator gone (dismissed) — system is green
        log_info "System is healthy (Ready)"
        return 0
    done

    # Timeout: health check didn't complete in 20s — warn but continue
    log_info "Warning: Health check did not complete within 20s, proceeding anyway"
}

_pb_get_label() {
    # Extract the accessibility label for an element by identifier.
    # Pipes directly from peekaboo to python to avoid bash variable corruption.
    local identifier="$1"

    _pb_activate_app
    peekaboo see --app KeyPath --json 2>/dev/null | python3 -c "
import json, sys
identifier = sys.argv[1]
raw = sys.stdin.buffer.read().decode('utf-8', errors='replace')
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(1)
elements = data.get('data', {}).get('ui_elements', [])
for e in elements:
    if e.get('identifier') == identifier:
        print(e.get('label', ''))
        sys.exit(0)
sys.exit(1)
" "$identifier" 2>/dev/null
}

quit_app() {
    # Gracefully quit KeyPath, with escalating force.
    log_info "Quitting KeyPath..."

    # Try graceful quit via AppleScript
    osascript -e 'tell application "KeyPath" to quit' 2>/dev/null || true
    sleep 2

    # Try peekaboo quit
    if pgrep -x "KeyPath" > /dev/null 2>&1; then
        peekaboo app quit --app KeyPath >/dev/null 2>&1 || true
        sleep 2
    fi

    # Force kill if still running
    if pgrep -x "KeyPath" > /dev/null 2>&1; then
        log_info "Force-killing KeyPath..."
        killall -9 "KeyPath" 2>/dev/null || true
        sleep 1
    fi

    # Verify it's gone
    if pgrep -x "KeyPath" > /dev/null 2>&1; then
        log_fail "Could not kill KeyPath"
        return 1
    fi
    log_info "KeyPath stopped"
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
