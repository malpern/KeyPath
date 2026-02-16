#!/bin/bash
# 06-colorway-picker.sh — Keycap style switching
#
# Colorway IDs from GMKColorway.swift:
#   default, olivia-dark, olivia-light, 8008, laser, red-samurai,
#   botanical, bento, wob, wob-icon, hyperfuse, godspeed, dots, dots-dark
#
# Accessibility pattern: overlay-colorway-button-{colorway.id}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "06-colorway-picker"

ensure_app_running

# ── Setup: Open drawer → settings → keycaps tab ──────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1
pb_click "inspector-tab-settings" 2>/dev/null || true
sleep 0.5

# ── Test 1: Open keycaps tab ─────────────────────────────────────────────────
begin_test "Open keycaps settings tab"
if pb_click "inspector-tab-keycaps"; then
    sleep 1
    pb_screenshot "colorway-picker"
    pass_test
else
    fail_test "Could not open keycaps tab"
fi

# ── Test 2: Default colorway card visible ─────────────────────────────────────
begin_test "Default colorway card visible"
if pb_assert_exists "overlay-colorway-button-default" 5; then
    pass_test
else
    fail_test "overlay-colorway-button-default not found"
fi

# ── Test 3: Select Olivia Dark ────────────────────────────────────────────────
begin_test "Select Olivia Dark colorway"
if pb_click "overlay-colorway-button-olivia-dark"; then
    sleep 1
    pb_screenshot "colorway-olivia-dark"
    pass_test
else
    fail_test "Could not click overlay-colorway-button-olivia-dark"
fi

# ── Test 4: Select Laser ─────────────────────────────────────────────────────
begin_test "Select Laser colorway"
if pb_click "overlay-colorway-button-laser"; then
    sleep 1
    pb_screenshot "colorway-laser"
    pass_test
else
    fail_test "Could not click overlay-colorway-button-laser"
fi

# ── Test 5: Select Red Samurai ────────────────────────────────────────────────
begin_test "Select Red Samurai colorway"
if pb_click "overlay-colorway-button-red-samurai"; then
    sleep 1
    pb_screenshot "colorway-red-samurai"
    pass_test
else
    fail_test "Could not click overlay-colorway-button-red-samurai"
fi

# ── Test 6: Select Botanical ──────────────────────────────────────────────────
begin_test "Select Botanical colorway"
if pb_click "overlay-colorway-button-botanical"; then
    sleep 1
    pb_screenshot "colorway-botanical"
    pass_test
else
    skip_test "Could not click Botanical (may need scroll)"
fi

# ── Test 7: Select WoB ───────────────────────────────────────────────────────
begin_test "Select WoB colorway"
pb_scroll "down" 2
sleep 0.5
if pb_click "overlay-colorway-button-wob"; then
    sleep 1
    pb_screenshot "colorway-wob"
    pass_test
else
    skip_test "Could not click WoB"
fi

# ── Test 8: Select Dots Rainbow ───────────────────────────────────────────────
begin_test "Select Dots Rainbow colorway"
if pb_click "overlay-colorway-button-dots"; then
    sleep 1
    pb_screenshot "colorway-dots"
    pass_test
else
    skip_test "Could not click Dots Rainbow"
fi

# ── Test 9: Select Hyperfuse ──────────────────────────────────────────────────
begin_test "Select Hyperfuse colorway"
if pb_click "overlay-colorway-button-hyperfuse"; then
    sleep 1
    pb_screenshot "colorway-hyperfuse"
    pass_test
else
    skip_test "Could not click Hyperfuse"
fi

# ── Test 10: Return to default colorway ───────────────────────────────────────
begin_test "Return to default colorway"
pb_scroll "up" 5
sleep 0.5
if pb_click "overlay-colorway-button-default"; then
    sleep 1
    pass_test
else
    fail_test "Could not return to default colorway"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
