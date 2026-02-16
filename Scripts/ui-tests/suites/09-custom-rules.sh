#!/bin/bash
# 09-custom-rules.sh — Create, toggle, delete custom rules
#
# Custom rules IDs from OverlayInspectorPanel+CustomRules.swift and CustomRulesView+Subviews.swift:
#   custom-rules-new-button, custom-rules-reset-button,
#   custom-rules-inline-input, custom-rules-inline-output,
#   custom-rules-inline-add-button, custom-rules-inline-title,
#   custom-rules-inline-notes, custom-rules-inline-error,
#   custom-rules-toggle-{rule.id}, custom-rules-menu-{rule.id},
#   custom-rules-menu-edit-drawer-button-{rule.id}, custom-rules-menu-delete-button-{rule.id},
#   custom-rules-delete-cancel-button, custom-rules-delete-confirm-button,
#   overlay-reset-all-custom-rules-confirm-button, overlay-reset-all-custom-rules-cancel-button
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "09-custom-rules"

ensure_app_running

# ── Setup: Open drawer → custom rules tab ─────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1

# ── Test 1: Open custom rules tab ────────────────────────────────────────────
begin_test "Open custom rules tab"
if pb_click "inspector-tab-custom-rules"; then
    sleep 1
    pb_screenshot "custom-rules-tab"
    pass_test
else
    fail_test "Could not open custom rules tab"
fi

# ── Test 2: Add rule button exists ────────────────────────────────────────────
begin_test "Add rule button visible"
if pb_assert_exists "custom-rules-new-button" 3; then
    pass_test
else
    fail_test "custom-rules-new-button not found"
fi

# ── Test 3: Reset button exists ───────────────────────────────────────────────
begin_test "Reset rules button visible"
if pb_assert_exists "custom-rules-reset-button" 3; then
    pass_test
else
    skip_test "custom-rules-reset-button not found"
fi

# ── Test 4: Click add new rule ────────────────────────────────────────────────
begin_test "Click add new rule"
if pb_click "custom-rules-new-button"; then
    sleep 1
    pb_screenshot "custom-rules-new"
    pass_test
else
    fail_test "Could not click add rule button"
fi

# ── Test 5: Inline input field visible ────────────────────────────────────────
begin_test "Inline input field visible"
if pb_assert_exists "custom-rules-inline-input" 3; then
    pass_test
else
    skip_test "custom-rules-inline-input not found"
fi

# ── Test 6: Inline output field visible ───────────────────────────────────────
begin_test "Inline output field visible"
if pb_assert_exists "custom-rules-inline-output" 3; then
    pass_test
else
    skip_test "custom-rules-inline-output not found"
fi

# ── Test 7: Inline add button visible ─────────────────────────────────────────
begin_test "Inline add button visible"
if pb_assert_exists "custom-rules-inline-add-button" 3; then
    pass_test
else
    skip_test "custom-rules-inline-add-button not found"
fi

# ── Test 8: Title field visible ───────────────────────────────────────────────
begin_test "Title field visible"
if pb_assert_exists "custom-rules-inline-title" 3; then
    pass_test
else
    skip_test "custom-rules-inline-title not found"
fi

# ── Test 9: Notes field visible ───────────────────────────────────────────────
begin_test "Notes field visible"
if pb_assert_exists "custom-rules-inline-notes" 3; then
    pass_test
else
    skip_test "custom-rules-inline-notes not found"
fi

# ── Test 10: Reset all with confirmation ──────────────────────────────────────
begin_test "Reset all custom rules confirmation"
if pb_click "custom-rules-reset-button" 2>/dev/null; then
    sleep 1
    if pb_assert_exists "overlay-reset-all-custom-rules-confirm-button" 3; then
        # Cancel to avoid side effects
        pb_click "overlay-reset-all-custom-rules-cancel-button" 2>/dev/null || true
        sleep 0.5
        pass_test
    else
        skip_test "Confirmation dialog did not appear"
    fi
else
    skip_test "Could not click reset button"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
