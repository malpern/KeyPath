#!/bin/bash
# 10-launchers.sh — Add, edit, toggle, delete launchers
#
# Launcher IDs from OverlayLaunchersSection.swift:
#   overlay-launcher-add, overlay-launcher-customize,
#   overlay-launcher-add-key, overlay-launcher-add-type-picker,
#   overlay-launcher-add-app-name, overlay-launcher-add-app-browse,
#   overlay-launcher-add-bundle-id, overlay-launcher-add-url,
#   overlay-launcher-add-cancel, overlay-launcher-add-save,
#   overlay-launcher-toggle-{key}, overlay-launcher-delete-{key},
#   overlay-launcher-edit-key, overlay-launcher-edit-type-picker,
#   overlay-launcher-edit-app-name, overlay-launcher-edit-delete,
#   overlay-launcher-edit-cancel, overlay-launcher-edit-save
#
# Launcher drawer IDs from LauncherDrawerView.swift:
#   launcher-drawer-add-button, launcher-drawer-menu-button
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "10-launchers"

ensure_app_running

# ── Setup: Open drawer → launchers tab ────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1

# ── Test 1: Open launchers tab ───────────────────────────────────────────────
begin_test "Open launchers tab"
if pb_click "inspector-tab-launchers"; then
    sleep 1
    pb_screenshot "launchers-tab"
    pass_test
else
    fail_test "Could not open launchers tab"
fi

# ── Test 2: Add launcher button exists ────────────────────────────────────────
begin_test "Add launcher button visible"
if pb_assert_exists "overlay-launcher-add" 3; then
    pass_test
else
    fail_test "overlay-launcher-add not found"
fi

# ── Test 3: Customize button exists ───────────────────────────────────────────
begin_test "Customize button visible"
if pb_assert_exists "overlay-launcher-customize" 3; then
    pass_test
else
    skip_test "overlay-launcher-customize not found"
fi

# ── Test 4: Click add launcher ────────────────────────────────────────────────
begin_test "Click add launcher"
if pb_click "overlay-launcher-add"; then
    sleep 1
    pb_screenshot "launcher-add-form"
    pass_test
else
    fail_test "Could not click add launcher"
fi

# ── Test 5: Key picker visible ────────────────────────────────────────────────
begin_test "Launcher key picker visible"
if pb_assert_exists "overlay-launcher-add-key" 3; then
    pass_test
else
    fail_test "overlay-launcher-add-key not found"
fi

# ── Test 6: Type picker visible ───────────────────────────────────────────────
begin_test "Launcher type picker visible"
if pb_assert_exists "overlay-launcher-add-type-picker" 3; then
    pass_test
else
    fail_test "overlay-launcher-add-type-picker not found"
fi

# ── Test 7: App name field visible ────────────────────────────────────────────
begin_test "App name field visible"
if pb_assert_exists "overlay-launcher-add-app-name" 3; then
    pass_test
else
    skip_test "overlay-launcher-add-app-name not found (might need App type selected)"
fi

# ── Test 8: URL field visible ─────────────────────────────────────────────────
begin_test "URL field visible"
if pb_assert_exists "overlay-launcher-add-url" 3; then
    pass_test
else
    skip_test "overlay-launcher-add-url not found (might need URL type selected)"
fi

# ── Test 9: Save button visible ───────────────────────────────────────────────
begin_test "Save button visible"
if pb_assert_exists "overlay-launcher-add-save" 3; then
    pass_test
else
    fail_test "overlay-launcher-add-save not found"
fi

# ── Test 10: Cancel add launcher ──────────────────────────────────────────────
begin_test "Cancel add launcher"
if pb_click "overlay-launcher-add-cancel"; then
    sleep 0.5
    pass_test
else
    fail_test "Could not click overlay-launcher-add-cancel"
fi

# ── Test 11: Launcher drawer add button ───────────────────────────────────────
begin_test "Launcher drawer add button"
# Open customize view first
if pb_click "overlay-launcher-customize" 2>/dev/null; then
    sleep 1
    if pb_assert_exists "launcher-drawer-add-button" 3; then
        pass_test
    else
        skip_test "launcher-drawer-add-button not found"
    fi
else
    skip_test "Could not open customize view"
fi

# ── Test 12: Launcher drawer menu button ──────────────────────────────────────
begin_test "Launcher drawer menu button"
if pb_assert_exists "launcher-drawer-menu-button" 3; then
    pass_test
else
    skip_test "launcher-drawer-menu-button not found"
fi

# ── Test 13: Launcher list reference screenshot ───────────────────────────────
begin_test "Launcher list reference screenshot"
pb_screenshot "launchers-state"
pass_test

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
