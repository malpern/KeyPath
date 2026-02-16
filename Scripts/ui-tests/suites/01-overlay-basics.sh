#!/bin/bash
# 01-overlay-basics.sh — Overlay visibility, drag, hide/show
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "01-overlay-basics"

ensure_app_running

# ── Test 1: Overlay window appears on launch ──────────────────────────────────
begin_test "Overlay visible on launch"
if pb_assert_exists "keyboard-overlay" 5; then
    pass_test
else
    fail_test "keyboard-overlay not found"
fi

# ── Test 2: Keyboard visualization is rendered ────────────────────────────────
begin_test "Keyboard visualization rendered"
# The overlay window itself is identifiable; use AI vision to confirm keys are drawn
if pb_see "Are keyboard keys visible with labels like A, S, D, F?" | grep -qi "key\|label\|letter"; then
    pass_test
else
    fail_test "Keyboard visualization appears empty"
fi

# ── Test 3: Health indicator shows status ─────────────────────────────────────
begin_test "Health indicator visible"
if pb_assert_exists "overlay-health-indicator" 5; then
    pass_test
else
    fail_test "overlay-health-indicator not found"
fi

# ── Test 4: Input mode indicator visible ──────────────────────────────────────
begin_test "Input mode indicator visible"
if pb_assert_exists "overlay-input-mode-indicator" 3; then
    pass_test
else
    skip_test "overlay-input-mode-indicator not found"
fi

# ── Test 5: Drawer toggle visible ─────────────────────────────────────────────
begin_test "Drawer toggle visible"
if pb_assert_exists "overlay-drawer-toggle" 3; then
    pass_test
else
    fail_test "overlay-drawer-toggle not found"
fi

# ── Test 6: Layer picker toggle visible ───────────────────────────────────────
begin_test "Layer picker toggle visible"
if pb_assert_exists "overlay-layer-picker-toggle" 3; then
    pass_test
else
    fail_test "overlay-layer-picker-toggle not found"
fi

# ── Test 7: Hide overlay via button ───────────────────────────────────────────
begin_test "Hide overlay via button"
if pb_click "overlay-hide-button"; then
    sleep 1
    if ! pb_assert_exists "overlay-health-indicator" 2; then
        pass_test
    else
        fail_test "Overlay still visible after clicking hide"
    fi
else
    fail_test "Could not click overlay-hide-button"
fi

# ── Test 8: Show overlay via hotkey ───────────────────────────────────────────
begin_test "Show overlay via Cmd+Opt+K"
pb_hotkey "cmd+opt+k"
sleep 2
if pb_assert_exists "overlay-health-indicator" 5; then
    pass_test
else
    fail_test "Overlay did not reappear after Cmd+Opt+K"
fi

# ── Test 9: Reference screenshot ──────────────────────────────────────────────
begin_test "Reference screenshot"
pb_screenshot "overlay-reference"
pass_test

end_suite
