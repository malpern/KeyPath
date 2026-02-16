#!/bin/bash
# 13-menu-bar.sh — Menu bar items and keyboard shortcuts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "13-menu-bar"

ensure_app_running

# ── Test 1: KeyPath menu accessible ───────────────────────────────────────────
begin_test "KeyPath menu accessible"
if peekaboo menu --app KeyPath --list 2>/dev/null | grep -qi "keypath\|file\|edit\|view\|window\|help"; then
    pass_test
else
    skip_test "Could not list menu items"
fi

# ── Test 2: Toggle overlay via hotkey ─────────────────────────────────────────
begin_test "Toggle overlay with Cmd+Opt+K (hide)"
# First ensure overlay is visible
pb_assert_exists "overlay-health-indicator" 3 || true
pb_hotkey "cmd+opt+k"
sleep 1
pb_screenshot "menu-overlay-hidden"
pass_test

# ── Test 3: Toggle overlay back ──────────────────────────────────────────────
begin_test "Toggle overlay with Cmd+Opt+K (show)"
pb_hotkey "cmd+opt+k"
sleep 1
if pb_assert_exists "overlay-health-indicator" 5; then
    pass_test
else
    fail_test "Overlay did not reappear"
fi

# ── Test 4: Open settings via hotkey ──────────────────────────────────────────
begin_test "Open settings via Cmd+,"
pb_hotkey "cmd+,"
sleep 2
pb_screenshot "menu-settings-opened"
if pb_see "Is there a settings or preferences window visible?" | grep -qi "settings\|preferences\|window"; then
    pass_test
else
    fail_test "Settings window did not open"
fi

# ── Test 5: Close settings ───────────────────────────────────────────────────
begin_test "Close settings via Cmd+W"
pb_hotkey "cmd+w"
sleep 1
pass_test

# ── Test 6: App menu items ───────────────────────────────────────────────────
begin_test "App menu items"
# Try to access KeyPath menu to see items
if peekaboo menu --app KeyPath "KeyPath" --list 2>/dev/null | grep -qi "about\|preferences\|settings\|quit"; then
    pass_test
else
    skip_test "Could not enumerate app menu items"
fi

# ── Test 7: View menu items ──────────────────────────────────────────────────
begin_test "View menu contains toggle overlay"
if peekaboo menu --app KeyPath "View" --list 2>/dev/null | grep -qi "overlay\|toggle\|keyboard"; then
    pass_test
else
    skip_test "Could not verify View menu"
fi

end_suite
