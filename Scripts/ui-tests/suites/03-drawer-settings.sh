#!/bin/bash
# 03-drawer-settings.sh — Drawer toggle, settings shelf tabs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "03-drawer-settings"

ensure_app_running

# ── Test 1: Drawer toggle exists ──────────────────────────────────────────────
begin_test "Drawer toggle visible"
if pb_assert_exists "overlay-drawer-toggle" 5; then
    pass_test
else
    fail_test "overlay-drawer-toggle not found"
fi

# ── Test 2: Open drawer ──────────────────────────────────────────────────────
begin_test "Open drawer"
if pb_click "overlay-drawer-toggle"; then
    sleep 1
    pb_screenshot "drawer-opened"
    pass_test
else
    fail_test "Could not click drawer toggle"
fi

# ── Test 3: Default tab is active ─────────────────────────────────────────────
begin_test "Default tab active"
# Check that at least one inspector tab is visible
if pb_assert_exists "inspector-tab-mapper" 3 || pb_assert_exists "inspector-tab-custom-rules" 3; then
    pass_test
else
    fail_test "No inspector tab found in drawer"
fi

# ── Test 4: Settings gear opens settings shelf ────────────────────────────────
begin_test "Open settings shelf"
if pb_click "inspector-tab-settings"; then
    sleep 1
    pb_screenshot "settings-shelf-opened"
    pass_test
else
    fail_test "Could not click inspector-tab-settings"
fi

# ── Test 5: Layout tab visible in settings ────────────────────────────────────
begin_test "Layout settings tab visible"
if pb_assert_exists "inspector-tab-layout" 3; then
    pass_test
else
    fail_test "inspector-tab-layout not found"
fi

# ── Test 6: Keymap tab visible ────────────────────────────────────────────────
begin_test "Keymap settings tab visible"
if pb_assert_exists "inspector-tab-keymap" 3; then
    pass_test
else
    fail_test "inspector-tab-keymap not found"
fi

# ── Test 7: Keycaps tab visible ───────────────────────────────────────────────
begin_test "Keycaps settings tab visible"
if pb_assert_exists "inspector-tab-keycaps" 3; then
    pass_test
else
    fail_test "inspector-tab-keycaps not found"
fi

# ── Test 8: Sounds tab visible ────────────────────────────────────────────────
begin_test "Sounds settings tab visible"
if pb_assert_exists "inspector-tab-sounds" 3; then
    pass_test
else
    fail_test "inspector-tab-sounds not found"
fi

# ── Test 9: Click each settings tab ───────────────────────────────────────────
begin_test "Navigate settings tabs"
local_pass=true
for tab in inspector-tab-layout inspector-tab-keymap inspector-tab-keycaps inspector-tab-sounds; do
    if pb_click "$tab"; then
        sleep 0.5
    else
        local_pass=false
        break
    fi
done
if $local_pass; then
    pass_test
else
    fail_test "Could not click all settings tabs"
fi

# ── Test 10: Collapse settings shelf ──────────────────────────────────────────
begin_test "Collapse settings shelf"
if pb_click "inspector-tab-settings"; then
    sleep 0.5
    pass_test
else
    fail_test "Could not collapse settings shelf"
fi

# ── Test 11: Close drawer ─────────────────────────────────────────────────────
begin_test "Close drawer"
if pb_click "overlay-drawer-toggle"; then
    sleep 1
    pb_screenshot "drawer-closed"
    pass_test
else
    fail_test "Could not close drawer"
fi

end_suite
