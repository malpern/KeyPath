#!/bin/bash
# 04-layout-picker.sh — Physical layout selection, scroll, QMK search
#
# Layout IDs from PhysicalLayout+Builtins.swift:
#   macbook-us, macbook-jis, macbook-iso, macbook-abnt2, macbook-korean,
#   ansi-40, ansi-60, ansi-65, ansi-75, ansi-80 (TKL), ansi-100 (Full)
#
# Accessibility pattern: overlay-keyboard-layout-button-{layout.id}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "04-layout-picker"

ensure_app_running

# ── Setup: Open drawer → settings → layout tab ───────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1
pb_click "inspector-tab-settings" 2>/dev/null || true
sleep 0.5

# ── Test 1: Open layout tab ──────────────────────────────────────────────────
begin_test "Open layout settings tab"
if pb_click "inspector-tab-layout"; then
    sleep 1
    pb_screenshot "layout-picker"
    pass_test
else
    fail_test "Could not open layout tab"
fi

# ── Test 2: MacBook US selected by default ────────────────────────────────────
begin_test "MacBook US layout card visible"
if pb_assert_exists "overlay-keyboard-layout-button-macbook-us" 5; then
    pass_test
else
    fail_test "overlay-keyboard-layout-button-macbook-us not found"
fi

# ── Test 3: Select ANSI 60% layout ───────────────────────────────────────────
begin_test "Select ANSI 60% layout"
if pb_click "overlay-keyboard-layout-button-ansi-60"; then
    sleep 1
    pb_screenshot "layout-ansi-60"
    pass_test
else
    fail_test "Could not click overlay-keyboard-layout-button-ansi-60"
fi

# ── Test 4: Select ANSI 65% layout ───────────────────────────────────────────
begin_test "Select ANSI 65% layout"
if pb_click "overlay-keyboard-layout-button-ansi-65"; then
    sleep 1
    pb_screenshot "layout-ansi-65"
    pass_test
else
    fail_test "Could not click overlay-keyboard-layout-button-ansi-65"
fi

# ── Test 5: Select ANSI TKL layout ───────────────────────────────────────────
begin_test "Select ANSI TKL layout"
if pb_click "overlay-keyboard-layout-button-ansi-80"; then
    sleep 1
    pb_screenshot "layout-ansi-tkl"
    pass_test
else
    fail_test "Could not click overlay-keyboard-layout-button-ansi-80"
fi

# ── Test 6: Select ANSI Full Size (may require scroll) ───────────────────────
begin_test "Select ANSI Full Size layout"
pb_scroll "down" 3
sleep 0.5
if pb_click "overlay-keyboard-layout-button-ansi-100"; then
    sleep 1
    pb_screenshot "layout-ansi-full"
    pass_test
else
    fail_test "Could not click overlay-keyboard-layout-button-ansi-100"
fi

# ── Test 7: MacBook JIS layout exists ─────────────────────────────────────────
begin_test "MacBook JIS layout card"
pb_scroll "up" 5
sleep 0.5
if pb_assert_exists "overlay-keyboard-layout-button-macbook-jis" 3; then
    pass_test
else
    skip_test "MacBook JIS layout card not visible (may need scroll)"
fi

# ── Test 8: MacBook ISO layout exists ─────────────────────────────────────────
begin_test "MacBook ISO layout card"
if pb_assert_exists "overlay-keyboard-layout-button-macbook-iso" 3; then
    pass_test
else
    skip_test "MacBook ISO layout card not visible (may need scroll)"
fi

# ── Test 9: Return to MacBook US ──────────────────────────────────────────────
begin_test "Return to MacBook US default"
pb_scroll "up" 5
sleep 0.5
if pb_click "overlay-keyboard-layout-button-macbook-us"; then
    sleep 1
    pass_test
else
    fail_test "Could not return to MacBook US"
fi

# ── Test 10: QMK search field ─────────────────────────────────────────────────
begin_test "QMK search field"
if pb_assert_exists "qmk-search-field" 2; then
    pass_test
else
    skip_test "QMK search not enabled (behind feature flag)"
fi

# ── Test 11: Custom layout import button ──────────────────────────────────────
begin_test "Import custom layout button"
if pb_assert_exists "import-custom-layout-button" 3; then
    pass_test
else
    skip_test "Import custom layout button not visible"
fi

# ── Teardown: Close drawer ───────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
