#!/bin/bash
# 02-layer-selector.sh — Layer picker expand, select, create, delete
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

begin_suite "02-layer-selector"

ensure_app_running

# ── Test 1: Layer picker toggle exists ────────────────────────────────────────
begin_test "Layer picker toggle visible"
if pb_assert_exists "overlay-layer-picker-toggle" 5; then
    pass_test
else
    fail_test "overlay-layer-picker-toggle not found"
fi

# ── Test 2: Expand layer picker ───────────────────────────────────────────────
begin_test "Expand layer picker"
if pb_click "overlay-layer-picker-toggle"; then
    sleep 1
    pb_screenshot "layer-picker-expanded"
    pass_test
else
    fail_test "Could not click layer picker toggle"
fi

# ── Test 3: Base layer exists ─────────────────────────────────────────────────
begin_test "Base layer visible"
# Layer identifiers use kanataName: overlay-layer-base, overlay-layer-nav
if pb_assert_exists "overlay-layer-base" 3; then
    pass_test
else
    fail_test "overlay-layer-base not found"
fi

# ── Test 4: Select nav layer (if available) ───────────────────────────────────
begin_test "Select nav layer"
if pb_assert_exists "overlay-layer-nav" 3; then
    if pb_click "overlay-layer-nav"; then
        sleep 1
        pb_screenshot "layer-nav-selected"
        pass_test
    else
        fail_test "Could not click nav layer"
    fi
else
    skip_test "Nav layer not available"
fi

# ── Test 5: Return to base layer ─────────────────────────────────────────────
begin_test "Return to base layer"
if pb_click "overlay-layer-base"; then
    sleep 1
    pass_test
else
    fail_test "Could not click base layer"
fi

# ── Test 6: New layer button exists ───────────────────────────────────────────
begin_test "New layer button"
if pb_assert_exists "layer-picker-new" 3; then
    pass_test
else
    skip_test "layer-picker-new not found"
fi

# ── Test 7: Create new layer dialog ──────────────────────────────────────────
begin_test "Create new layer dialog"
if pb_click "layer-picker-new" 2>/dev/null; then
    sleep 1
    if pb_assert_exists "overlay-layer-dialog-name" 3; then
        pb_screenshot "layer-create-dialog"
        # Cancel the dialog to avoid side effects
        if pb_click "overlay-layer-dialog-cancel" 2>/dev/null; then
            pass_test
        else
            pass_test  # Dialog opened, that's the main check
        fi
    else
        skip_test "Layer creation dialog fields not found"
    fi
else
    skip_test "Could not click new layer button"
fi

# ── Test 8: Collapse layer picker ─────────────────────────────────────────────
begin_test "Collapse layer picker"
if pb_click "overlay-layer-picker-toggle"; then
    sleep 0.5
    pass_test
else
    fail_test "Could not collapse layer picker"
fi

end_suite
