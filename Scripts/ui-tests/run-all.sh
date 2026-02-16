#!/bin/bash
# run-all.sh — Master runner for KeyPath Peekaboo UI automation tests.
#
# Builds, deploys, runs all test suites, resets defaults, and prints results.
#
# Usage:
#   ./Scripts/ui-tests/run-all.sh           # Run all suites
#   ./Scripts/ui-tests/run-all.sh --skip-build  # Skip build, run suites only
#   ./Scripts/ui-tests/run-all.sh 01 03     # Run specific suites by number

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

SKIP_BUILD=0
SPECIFIC_SUITES=()

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --skip-build)
            SKIP_BUILD=1
            ;;
        *)
            SPECIFIC_SUITES+=("$arg")
            ;;
    esac
done

# ── 1. Build and deploy ───────────────────────────────────────────────────────
if [[ $SKIP_BUILD -eq 0 ]]; then
    echo -e "${BOLD}=== Building and deploying KeyPath ===${NC}"
    SKIP_NOTARIZE=1 "$SCRIPT_DIR/../../build.sh"
    echo ""
fi

# ── 2. Reset to clean state ───────────────────────────────────────────────────
echo -e "${BOLD}=== Resetting to clean state ===${NC}"
quit_app
# Verify KeyPath is fully stopped before resetting
if pgrep -x "KeyPath" > /dev/null 2>&1; then
    log_fail "KeyPath still running after quit — forcing kill"
    killall -9 "KeyPath" 2>/dev/null || true
    sleep 2
fi
bash "$SCRIPT_DIR/lib/reset-defaults.sh"
echo ""

# ── 3. Launch app in test mode ─────────────────────────────────────────────────
echo -e "${BOLD}=== Launching KeyPath in test mode ===${NC}"
ensure_app_running
echo ""

# ── 4. Run suites ─────────────────────────────────────────────────────────────
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
SUITES_RUN=0
SUITES_WITH_FAILURES=0
FAILED_SUITES=()

run_suite() {
    local suite_path="$1"
    local suite_name
    suite_name=$(basename "$suite_path" .sh)

    echo -e "${BOLD}=== Running $suite_name ===${NC}"

    if bash "$suite_path"; then
        log_pass "Suite $suite_name completed successfully"
    else
        log_fail "Suite $suite_name had failures"
        SUITES_WITH_FAILURES=$(( SUITES_WITH_FAILURES + 1 ))
        FAILED_SUITES+=("$suite_name")
    fi
    SUITES_RUN=$(( SUITES_RUN + 1 ))
    echo ""
}

if [[ ${#SPECIFIC_SUITES[@]} -gt 0 ]]; then
    # Run specific suites
    for num in "${SPECIFIC_SUITES[@]}"; do
        suite_path="$SCRIPT_DIR/suites/${num}-*.sh"
        # shellcheck disable=SC2086
        for match in $suite_path; do
            if [[ -f "$match" ]]; then
                run_suite "$match"
            else
                log_fail "No suite matching: $num"
            fi
        done
    done
else
    # Run all suites in order
    for suite in "$SCRIPT_DIR/suites/"*.sh; do
        if [[ -f "$suite" ]]; then
            run_suite "$suite"
        fi
    done
fi

# ── 5. Reset to defaults ──────────────────────────────────────────────────────
echo -e "${BOLD}=== Resetting to defaults ===${NC}"
quit_app
bash "$SCRIPT_DIR/lib/reset-defaults.sh"
echo ""

# ── 6. Restart app in normal mode ─────────────────────────────────────────────
echo -e "${BOLD}=== Restarting KeyPath in normal mode ===${NC}"
open -a KeyPath
echo ""

# ── 7. Print results ──────────────────────────────────────────────────────────
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  UI Test Results${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Suites run:           $SUITES_RUN"
echo -e "  ${RED}Suites with failures: $SUITES_WITH_FAILURES${NC}"

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}Failed suites:${NC}"
    for s in "${FAILED_SUITES[@]}"; do
        echo -e "    - $s"
    done
fi

echo ""
echo -e "  Screenshots: $RESULTS_DIR/"
echo ""

# Exit with failure if any suites failed
[[ $SUITES_WITH_FAILURES -eq 0 ]]
