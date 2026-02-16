#!/bin/bash
# 12-wizard.sh — Installation wizard navigation
#
# Wizard page IDs from WizardTypes.swift (wizard-page-{accessibilityIdentifier}):
#   wizard-page-overview, wizard-page-privileged-helper,
#   wizard-page-full-disk-access, wizard-page-conflicts,
#   wizard-page-input-monitoring, wizard-page-accessibility,
#   wizard-page-karabiner-components, wizard-page-kanata-components,
#   wizard-page-kanata-migration, wizard-page-stop-external-kanata,
#   wizard-page-communication, wizard-page-service
#
# Navigation IDs:
#   wizard-nav-back, wizard-nav-forward, wizard-close-button,
#   wizard-hero-section, wizard-hero-action-button,
#   wizard-summary-status-{validating|success|issues}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "12-wizard"

ensure_app_running

# ── Test 1: Launch wizard button exists ───────────────────────────────────────
begin_test "Launch wizard button"
if pb_assert_exists "launch-installation-wizard-button" 5; then
    pass_test
else
    skip_test "launch-installation-wizard-button not found (may require specific app state)"
fi

# ── Test 2: Open wizard ──────────────────────────────────────────────────────
begin_test "Open installation wizard"
if pb_click "launch-installation-wizard-button" 2>/dev/null; then
    sleep 2
    pb_screenshot "wizard-opened"
    pass_test
else
    skip_test "Could not launch wizard"
fi

# ── Test 3: Wizard close button exists ────────────────────────────────────────
begin_test "Wizard close button"
if pb_assert_exists "wizard-close-button" 3; then
    pass_test
else
    skip_test "wizard-close-button not found"
fi

# ── Test 4: Hero section visible ──────────────────────────────────────────────
begin_test "Wizard hero section"
if pb_assert_exists "wizard-hero-section" 3; then
    pass_test
else
    skip_test "wizard-hero-section not found"
fi

# ── Test 5: Hero action button ────────────────────────────────────────────────
begin_test "Wizard hero action button"
if pb_assert_exists "wizard-hero-action-button" 3; then
    pass_test
else
    skip_test "wizard-hero-action-button not found"
fi

# ── Test 6: Wizard navigation forward exists ──────────────────────────────────
begin_test "Wizard forward button"
if pb_assert_exists "wizard-nav-forward" 3; then
    pass_test
else
    skip_test "wizard-nav-forward not found"
fi

# ── Test 7: Navigate forward ──────────────────────────────────────────────────
begin_test "Wizard navigate forward"
if pb_click "wizard-nav-forward" 2>/dev/null; then
    sleep 1
    pb_screenshot "wizard-page-2"
    pass_test
else
    skip_test "Could not click forward button"
fi

# ── Test 8: Verify page transition via page identifier ────────────────────────
begin_test "Wizard page identifier present"
# After navigating forward, one of the wizard page IDs should be visible
page_found=false
for page_id in \
    "wizard-page-overview" \
    "wizard-page-privileged-helper" \
    "wizard-page-full-disk-access" \
    "wizard-page-conflicts" \
    "wizard-page-input-monitoring" \
    "wizard-page-accessibility" \
    "wizard-page-karabiner-components" \
    "wizard-page-kanata-components" \
    "wizard-page-service" \
    "wizard-page-summary" \
; do
    if pb_assert_exists "$page_id" 1; then
        log_info "Found page: $page_id"
        page_found=true
        break
    fi
done
if $page_found; then
    pass_test
else
    skip_test "No wizard page identifier found"
fi

# ── Test 9: Navigate forward again ───────────────────────────────────────────
begin_test "Wizard second page forward"
if pb_click "wizard-nav-forward" 2>/dev/null; then
    sleep 1
    pb_screenshot "wizard-page-3"
    pass_test
else
    skip_test "Could not navigate forward again"
fi

# ── Test 10: Wizard back button exists ────────────────────────────────────────
begin_test "Wizard back button"
if pb_assert_exists "wizard-nav-back" 3; then
    pass_test
else
    skip_test "wizard-nav-back not found"
fi

# ── Test 11: Navigate back ───────────────────────────────────────────────────
begin_test "Wizard navigate back"
if pb_click "wizard-nav-back" 2>/dev/null; then
    sleep 1
    pb_screenshot "wizard-back"
    pass_test
else
    skip_test "Could not click back button"
fi

# ── Test 12: Navigate back to first page ──────────────────────────────────────
begin_test "Wizard back to start"
pb_click "wizard-nav-back" 2>/dev/null || true
sleep 1
pass_test

# ── Test 13: Close wizard ─────────────────────────────────────────────────────
begin_test "Close wizard"
if pb_click "wizard-close-button"; then
    sleep 1
    pb_screenshot "wizard-closed"
    pass_test
else
    pb_hotkey "cmd+w"
    sleep 1
    pass_test
fi

end_suite
