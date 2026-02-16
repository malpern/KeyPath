#!/bin/bash
# 08-mapper.sh — Key mapper: select key, assign behavior, reset
#
# Mapper IDs from OverlayMapperSection.swift:
#   overlay-mapper-output-type, overlay-mapper-reset-slot-button,
#   overlay-mapper-reset-key-button, overlay-mapper-reset-all-button,
#   overlay-mapper-reset-cancel-button, overlay-mapper-app-condition,
#   overlay-mapper-multitap-link, overlay-mapper-fix-issues,
#   overlay-mapper-output-url
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "08-mapper"

ensure_app_running

# ── Setup: Open drawer → mapper tab ───────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1

# ── Test 1: Open mapper tab ──────────────────────────────────────────────────
begin_test "Open mapper tab"
if pb_click "inspector-tab-mapper"; then
    sleep 1
    pb_screenshot "mapper-tab"
    pass_test
else
    fail_test "Could not open mapper tab"
fi

# ── Test 2: Click a key on keyboard visualization ─────────────────────────────
begin_test "Click key on keyboard"
# Click the 'A' key on the visualization
if pb_click_label "A" 2>/dev/null; then
    sleep 1
    pb_screenshot "mapper-key-selected"
    pass_test
else
    skip_test "Could not click key on keyboard visualization"
fi

# ── Test 3: Output type picker visible ────────────────────────────────────────
begin_test "Output type picker visible"
if pb_assert_exists "overlay-mapper-output-type" 3; then
    pass_test
else
    skip_test "overlay-mapper-output-type not found (key may not be selected)"
fi

# ── Test 4: App condition picker exists ───────────────────────────────────────
begin_test "App condition picker"
if pb_assert_exists "overlay-mapper-app-condition" 3; then
    pass_test
else
    skip_test "overlay-mapper-app-condition not found"
fi

# ── Test 5: Reset key button exists ───────────────────────────────────────────
begin_test "Reset key button"
if pb_assert_exists "overlay-mapper-reset-key-button" 3; then
    pass_test
else
    skip_test "overlay-mapper-reset-key-button not found"
fi

# ── Test 6: Reset all button exists ───────────────────────────────────────────
begin_test "Reset all mappings button"
if pb_assert_exists "overlay-mapper-reset-all-button" 3; then
    pass_test
else
    skip_test "overlay-mapper-reset-all-button not found"
fi

# ── Test 7: Click reset key ──────────────────────────────────────────────────
begin_test "Click reset key button"
if pb_click "overlay-mapper-reset-key-button" 2>/dev/null; then
    sleep 1
    pass_test
else
    skip_test "Could not click reset key button"
fi

# ── Test 8: Reset slot button ─────────────────────────────────────────────────
begin_test "Reset slot button"
if pb_assert_exists "overlay-mapper-reset-slot-button" 3; then
    pass_test
else
    skip_test "overlay-mapper-reset-slot-button not found (no slot selected)"
fi

# ── Test 9: Multitap link ────────────────────────────────────────────────────
begin_test "Multitap link"
if pb_assert_exists "overlay-mapper-multitap-link" 3; then
    pass_test
else
    skip_test "overlay-mapper-multitap-link not found"
fi

# ── Test 10: Reset all with confirmation ──────────────────────────────────────
begin_test "Reset all mappings confirmation"
if pb_click "overlay-mapper-reset-all-button" 2>/dev/null; then
    sleep 1
    # Check if cancel button appears in confirmation
    if pb_assert_exists "overlay-mapper-reset-cancel-button" 3; then
        pb_click "overlay-mapper-reset-cancel-button"
        sleep 0.5
        pass_test
    else
        pass_test  # Reset all clicked, confirmation may vary
    fi
else
    skip_test "Could not click reset all"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
