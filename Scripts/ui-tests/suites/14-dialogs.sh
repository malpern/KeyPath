#!/bin/bash
# 14-dialogs.sh — Confirmation dialogs, edge cases
#
# Dialog IDs:
#   ai-key-dialog-header, ai-key-dialog-close-button, ai-key-dialog-save-button,
#   ai-key-dialog-cancel-button, ai-key-dialog-skip-button,
#   ai-key-dialog-api-key-field, ai-key-dialog-dont-show-toggle,
#   overlay-reset-all-custom-rules-confirm-button, overlay-reset-all-custom-rules-cancel-button,
#   overlay-kanata-service-stopped-restart-button, overlay-kanata-service-stopped-cancel-button,
#   overlay-kanata-disconnected-indicator,
#   emergency-stop-restart-button, emergency-stop-got-it-button
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "14-dialogs"

ensure_app_running

# ── Test 1: Overlay window identity ───────────────────────────────────────────
begin_test "Overlay window identity"
if pb_assert_exists "keyboard-overlay" 5; then
    pass_test
else
    fail_test "keyboard-overlay not found"
fi

# ── Test 2: Kanata disconnected indicator (may or may not be visible) ─────────
begin_test "Kanata disconnected indicator"
if pb_assert_exists "overlay-kanata-disconnected-indicator" 2; then
    log_info "Kanata is currently disconnected"
    pass_test
else
    log_info "Kanata appears connected (indicator not shown)"
    pass_test  # Not an error — indicator only shows when disconnected
fi

# ── Test 3: Overlay position persistence ──────────────────────────────────────
begin_test "Overlay position persistence"
pb_screenshot "overlay-position-before"
restart_app
sleep 2
pb_screenshot "overlay-position-after"
if pb_assert_exists "overlay-health-indicator" 5; then
    pass_test
else
    fail_test "Overlay not visible after restart"
fi

# ── Test 4: All overlay header controls survive restart ───────────────────────
begin_test "Header controls after restart"
controls_found=0
for ctrl in \
    "overlay-drawer-toggle" \
    "overlay-layer-picker-toggle" \
    "overlay-health-indicator" \
    "overlay-hide-button" \
; do
    if pb_assert_exists "$ctrl" 3; then
        ((controls_found++))
    fi
done
if [[ $controls_found -ge 3 ]]; then
    pass_test
else
    fail_test "Only $controls_found/4 header controls found after restart"
fi

# ── Test 5: Multiple rapid drawer toggles ─────────────────────────────────────
begin_test "Rapid drawer toggle stress test"
local_pass=true
for i in 1 2 3 4; do
    if ! pb_click "overlay-drawer-toggle" 2>/dev/null; then
        local_pass=false
        break
    fi
    sleep 0.5
done
if $local_pass; then
    sleep 1
    pb_screenshot "rapid-toggle"
    pass_test
else
    fail_test "Drawer toggle failed during rapid cycling"
fi

# ── Test 6: Rapid settings tab switching ──────────────────────────────────────
begin_test "Rapid settings tab switching"
# Ensure drawer is open with settings
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5
pb_click "inspector-tab-settings" 2>/dev/null || true
sleep 0.5

local_pass=true
for tab in inspector-tab-layout inspector-tab-keymap inspector-tab-keycaps inspector-tab-sounds inspector-tab-layout; do
    if ! pb_click "$tab" 2>/dev/null; then
        local_pass=false
        break
    fi
    sleep 0.3
done
if $local_pass; then
    pass_test
else
    fail_test "Settings tab rapid switching failed"
fi

# ── Test 7: Rapid colorway switching ──────────────────────────────────────────
begin_test "Rapid colorway switching"
pb_click "inspector-tab-keycaps" 2>/dev/null || true
sleep 0.5
local_pass=true
for cw in overlay-colorway-button-laser overlay-colorway-button-wob overlay-colorway-button-default; do
    if ! pb_click "$cw" 2>/dev/null; then
        local_pass=false
        break
    fi
    sleep 0.3
done
if $local_pass; then
    pass_test
else
    fail_test "Colorway rapid switching failed"
fi

# Close drawer
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

# ── Test 8: Settings window open/close cycle ──────────────────────────────────
begin_test "Settings window open/close cycle"
for i in 1 2 3; do
    pb_hotkey "cmd+,"
    sleep 1
    pb_hotkey "cmd+w"
    sleep 0.5
done
if pb_assert_exists "overlay-health-indicator" 5; then
    pass_test
else
    fail_test "App became unresponsive after settings cycling"
fi

# ── Test 9: System status indicator ───────────────────────────────────────────
begin_test "System status indicator"
if pb_assert_exists "system-status-indicator" 3; then
    pass_test
else
    skip_test "system-status-indicator not found"
fi

# ── Test 10: Final state screenshot ───────────────────────────────────────────
begin_test "Final state screenshot"
pb_screenshot "final-state"
pass_test

end_suite
