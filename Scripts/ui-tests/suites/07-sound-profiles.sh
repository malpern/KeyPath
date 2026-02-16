#!/bin/bash
# 07-sound-profiles.sh — Typing sound selection
#
# Sound profile IDs from TypingSoundsManager.swift:
#   off, mx-blue, mx-brown, mx-red, nk-cream, bubble-pop
#
# Accessibility pattern: overlay-sound-profile-button-{profile.id}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "07-sound-profiles"

ensure_app_running

# ── Setup: Open drawer → settings → sounds tab ───────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 1
pb_click "inspector-tab-settings" 2>/dev/null || true
sleep 0.5

# ── Test 1: Open sounds tab ──────────────────────────────────────────────────
begin_test "Open sounds settings tab"
if pb_click "inspector-tab-sounds"; then
    sleep 1
    pb_screenshot "sound-profiles"
    pass_test
else
    fail_test "Could not open sounds tab"
fi

# ── Test 2: Off profile card visible ──────────────────────────────────────────
begin_test "Off sound profile card visible"
if pb_assert_exists "overlay-sound-profile-button-off" 5; then
    pass_test
else
    fail_test "overlay-sound-profile-button-off not found"
fi

# ── Test 3: Select Cherry MX Blue ─────────────────────────────────────────────
begin_test "Select Cherry MX Blue profile"
if pb_click "overlay-sound-profile-button-mx-blue"; then
    sleep 1
    pb_screenshot "sound-mx-blue"
    pass_test
else
    fail_test "Could not click overlay-sound-profile-button-mx-blue"
fi

# ── Test 4: Select Cherry MX Brown ────────────────────────────────────────────
begin_test "Select Cherry MX Brown profile"
if pb_click "overlay-sound-profile-button-mx-brown"; then
    sleep 1
    pass_test
else
    fail_test "Could not click overlay-sound-profile-button-mx-brown"
fi

# ── Test 5: Select Cherry MX Red ──────────────────────────────────────────────
begin_test "Select Cherry MX Red profile"
if pb_click "overlay-sound-profile-button-mx-red"; then
    sleep 1
    pass_test
else
    fail_test "Could not click overlay-sound-profile-button-mx-red"
fi

# ── Test 6: Select NK Cream ───────────────────────────────────────────────────
begin_test "Select NK Cream profile"
if pb_click "overlay-sound-profile-button-nk-cream"; then
    sleep 1
    pb_screenshot "sound-nk-cream"
    pass_test
else
    fail_test "Could not click overlay-sound-profile-button-nk-cream"
fi

# ── Test 7: Select Bubble Pop ─────────────────────────────────────────────────
begin_test "Select Bubble Pop profile"
if pb_click "overlay-sound-profile-button-bubble-pop"; then
    sleep 1
    pb_screenshot "sound-bubble-pop"
    pass_test
else
    fail_test "Could not click overlay-sound-profile-button-bubble-pop"
fi

# ── Test 8: Return to Off (silent) ────────────────────────────────────────────
begin_test "Return to Off (silent)"
if pb_click "overlay-sound-profile-button-off"; then
    sleep 1
    pass_test
else
    fail_test "Could not return to Off profile"
fi

# ── Teardown ──────────────────────────────────────────────────────────────────
pb_click "overlay-drawer-toggle" 2>/dev/null || true
sleep 0.5

end_suite
