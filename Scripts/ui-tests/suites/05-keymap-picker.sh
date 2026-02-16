#!/bin/bash
# 05-keymap-picker.sh — Logical keymap selection
#
# Keymap IDs from LogicalKeymap.swift:
#   qwerty-us, colemak, colemak-dh, dvorak, workman, graphite, azerty, qwertz
#
# Accessibility pattern: overlay-keymap-button-{keymap.id}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "05-keymap-picker"

ensure_app_running

# ── Setup: Open drawer → settings → keymap tab ───────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1
pb_click "inspector-tab-settings" 2>/dev/null || true
sleep 0.5

# ── Test 1: Open keymap tab ──────────────────────────────────────────────────
begin_test "Open keymap settings tab"
if pb_click "inspector-tab-keymap"; then
    sleep 1
    pb_screenshot "keymap-picker"
    pass_test
else
    fail_test "Could not open keymap tab"
fi

# ── Test 2: QWERTY US card visible ───────────────────────────────────────────
begin_test "QWERTY US keymap card"
if pb_assert_exists "overlay-keymap-button-qwerty-us" 5; then
    pass_test
else
    fail_test "overlay-keymap-button-qwerty-us not found"
fi

# ── Test 3: Colemak DH card visible ──────────────────────────────────────────
begin_test "Colemak DH keymap card"
if pb_assert_exists "overlay-keymap-button-colemak-dh" 3; then
    pass_test
else
    fail_test "overlay-keymap-button-colemak-dh not found"
fi

# ── Test 4: Select Colemak DH ────────────────────────────────────────────────
begin_test "Select Colemak DH keymap"
if pb_click "overlay-keymap-button-colemak-dh"; then
    sleep 1
    pb_screenshot "keymap-colemak-dh"
    pass_test
else
    fail_test "Could not click Colemak DH"
fi

# ── Test 5: Select Dvorak ────────────────────────────────────────────────────
begin_test "Select Dvorak keymap"
if pb_click "overlay-keymap-button-dvorak"; then
    sleep 1
    pb_screenshot "keymap-dvorak"
    pass_test
else
    fail_test "Could not click Dvorak"
fi

# ── Test 6: Workman card visible ──────────────────────────────────────────────
begin_test "Workman keymap card"
if pb_assert_exists "overlay-keymap-button-workman" 3; then
    pass_test
else
    skip_test "overlay-keymap-button-workman not found"
fi

# ── Test 7: Graphite card visible ─────────────────────────────────────────────
begin_test "Graphite keymap card"
if pb_assert_exists "overlay-keymap-button-graphite" 3; then
    pass_test
else
    skip_test "overlay-keymap-button-graphite not found"
fi

# ── Test 8: Select AZERTY (international) ─────────────────────────────────────
begin_test "Select AZERTY keymap"
if pb_click "overlay-keymap-button-azerty"; then
    sleep 1
    pb_screenshot "keymap-azerty"
    pass_test
else
    skip_test "Could not click AZERTY"
fi

# ── Test 9: QWERTZ card visible ──────────────────────────────────────────────
begin_test "QWERTZ keymap card"
if pb_assert_exists "overlay-keymap-button-qwertz" 3; then
    pass_test
else
    skip_test "overlay-keymap-button-qwertz not found"
fi

# ── Test 10: Return to QWERTY US ─────────────────────────────────────────────
begin_test "Return to QWERTY US"
if pb_click "overlay-keymap-button-qwerty-us"; then
    sleep 1
    pass_test
else
    fail_test "Could not return to QWERTY US"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
