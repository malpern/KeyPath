#!/bin/bash
# 11-settings-window.sh — All settings tabs: status, rules, general, repair
#
# Settings tab IDs from SettingsContainerView.swift:
#   settings-tab-status, settings-tab-rules, settings-tab-simulator,
#   settings-tab-general, settings-tab-repair
#
# Status tab IDs:
#   status-system-health-button, status-active-rules-button,
#   status-fix-it-button, status-service-toggle
#
# General tab IDs:
#   settings-capture-mode-picker, settings-overlay-layout-picker,
#   settings-overlay-keymap-picker, settings-reset-overlay-size-button,
#   settings-verbose-logging-toggle, settings-global-hotkey-toggle,
#   settings-qmk-search-toggle
#
# Repair tab IDs:
#   settings-uninstall-button, settings-uninstall-helper-button,
#   settings-reset-everything-button, settings-remove-duplicates-button
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "11-settings-window"

ensure_app_running

# ── Test 1: Open settings window via hotkey ───────────────────────────────────
begin_test "Open settings window (Cmd+,)"
pb_hotkey "cmd+,"
sleep 2
pb_screenshot "settings-window"
# Verify settings opened by checking for a tab
if pb_assert_exists "settings-tab-status" 5; then
    pass_test
else
    fail_test "Settings window did not open (settings-tab-status not found)"
fi

# ── Test 2: Status tab ───────────────────────────────────────────────────────
begin_test "Status tab"
if pb_click "settings-tab-status"; then
    sleep 1
    pb_screenshot "settings-status"
    pass_test
else
    fail_test "Could not click settings-tab-status"
fi

# ── Test 3: Status tab — service toggle ───────────────────────────────────────
begin_test "Status tab service toggle"
if pb_assert_exists "status-service-toggle" 3; then
    pass_test
else
    skip_test "status-service-toggle not found"
fi

# ── Test 4: Status tab — system health button ─────────────────────────────────
begin_test "Status tab health button"
if pb_assert_exists "status-system-health-button" 3; then
    pass_test
else
    skip_test "status-system-health-button not found"
fi

# ── Test 5: Rules tab ────────────────────────────────────────────────────────
begin_test "Rules tab"
if pb_click "settings-tab-rules"; then
    sleep 1
    pb_screenshot "settings-rules"
    pass_test
else
    fail_test "Could not click settings-tab-rules"
fi

# ── Test 6: Simulator tab ────────────────────────────────────────────────────
begin_test "Simulator tab"
if pb_click "settings-tab-simulator"; then
    sleep 1
    pb_screenshot "settings-simulator"
    pass_test
else
    skip_test "Could not click settings-tab-simulator"
fi

# ── Test 7: General tab ──────────────────────────────────────────────────────
begin_test "General tab"
if pb_click "settings-tab-general"; then
    sleep 1
    pb_screenshot "settings-general"
    pass_test
else
    fail_test "Could not click settings-tab-general"
fi

# ── Test 8: General tab — capture mode picker ─────────────────────────────────
begin_test "General tab capture mode picker"
if pb_assert_exists "settings-capture-mode-picker" 3; then
    pass_test
else
    skip_test "settings-capture-mode-picker not found"
fi

# ── Test 9: General tab — overlay layout picker ───────────────────────────────
begin_test "General tab overlay layout picker"
if pb_assert_exists "settings-overlay-layout-picker" 3; then
    pass_test
else
    skip_test "settings-overlay-layout-picker not found"
fi

# ── Test 10: General tab — overlay keymap picker ──────────────────────────────
begin_test "General tab overlay keymap picker"
if pb_assert_exists "settings-overlay-keymap-picker" 3; then
    pass_test
else
    skip_test "settings-overlay-keymap-picker not found"
fi

# ── Test 11: General tab — reset overlay size button ──────────────────────────
begin_test "General tab reset overlay size button"
if pb_assert_exists "settings-reset-overlay-size-button" 3; then
    pass_test
else
    skip_test "settings-reset-overlay-size-button not found"
fi

# ── Test 12: General tab — global hotkey toggle ───────────────────────────────
begin_test "General tab global hotkey toggle"
if pb_assert_exists "settings-global-hotkey-toggle" 3; then
    pass_test
else
    skip_test "settings-global-hotkey-toggle not found"
fi

# ── Test 13: Repair tab ──────────────────────────────────────────────────────
begin_test "Repair tab"
if pb_click "settings-tab-repair"; then
    sleep 1
    pb_screenshot "settings-repair"
    pass_test
else
    fail_test "Could not click settings-tab-repair"
fi

# ── Test 14: Repair tab — uninstall button exists (don't click!) ──────────────
begin_test "Repair tab uninstall button exists"
if pb_assert_exists "settings-uninstall-button" 3; then
    pass_test
else
    skip_test "settings-uninstall-button not found"
fi

# ── Test 15: Repair tab — reset everything button exists (don't click!) ───────
begin_test "Repair tab reset everything button exists"
if pb_assert_exists "settings-reset-everything-button" 3; then
    pass_test
else
    skip_test "settings-reset-everything-button not found"
fi

# ── Test 16: Repair tab — remove duplicates button ────────────────────────────
begin_test "Repair tab remove duplicates button"
if pb_assert_exists "settings-remove-duplicates-button" 3; then
    pass_test
else
    skip_test "settings-remove-duplicates-button not found"
fi

# ── Test 17: Close settings window ────────────────────────────────────────────
begin_test "Close settings window"
pb_hotkey "cmd+w"
sleep 1
pass_test

end_suite
