#!/bin/bash
# regenerate-screenshots.sh
#
# Regenerates all SwiftUI snapshot screenshots and copies them to Resources/
# for use in help documentation.
#
# This script:
#   1. Runs snapshot tests in RECORD mode (generates new reference PNGs)
#   2. Refreshes the CURATED doc images (those already git-tracked under
#      Resources/) from __Snapshots__/. Regression-only snapshots are skipped
#      so they don't leak into the app bundle as untracked noise.
#
# Usage:
#   ./Scripts/regenerate-screenshots.sh          # full regeneration
#   SKIP_PEEKABOO=1 ./Scripts/regenerate-screenshots.sh  # SwiftUI only
#   COPY_ALL=1 ./Scripts/regenerate-screenshots.sh       # copy every snapshot (discovery)
#
# Environment:
#   SKIP_PEEKABOO=1  - Skip Peekaboo system screenshots (requires app install + permissions)
#   COPY_ALL=1       - Copy every snapshot PNG, not just curated doc images (see Step 2)
#
# Called automatically by build-and-sign.sh during release builds.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
SNAPSHOTS_DIR="$PROJECT_DIR/Tests/KeyPathSnapshotTests/__Snapshots__"
RESOURCES_DIR="$PROJECT_DIR/Sources/KeyPathAppKit/Resources"

echo "📸 Regenerating screenshots..."

# -----------------------------------------------------------------------
# Step 1: Run snapshot tests in recording mode
# -----------------------------------------------------------------------
echo ""
echo "🔄 Running snapshot tests in RECORD mode..."
cd "$PROJECT_DIR"

# Record mode always exits non-zero (every test "fails" to remind you).
# We suppress the exit code and check for generated files instead.
KEYPATH_SNAPSHOTS=1 SNAPSHOT_RECORD=1 swift test --filter KeyPathSnapshotTests 2>&1 | \
    grep -E "(Test Case|Executed|passed|failed|error:)" || true

# Check if snapshots were generated
if [ ! -d "$SNAPSHOTS_DIR" ]; then
    echo "❌ ERROR: No snapshots generated at $SNAPSHOTS_DIR"
    exit 1
fi

SNAP_COUNT=$(find "$SNAPSHOTS_DIR" -name "*.png" | wc -l | tr -d ' ')
echo "✅ Generated $SNAP_COUNT snapshot images"

# -----------------------------------------------------------------------
# Step 2: Refresh curated doc screenshots in Resources
# -----------------------------------------------------------------------
# The snapshot suite exists mainly for visual-regression testing, so most of
# its PNGs are NOT help images. Only a curated subset is used in docs; those
# are the ones already git-tracked under Resources/. We refresh exactly those
# and skip the rest, so regression-only snapshots don't leak into the app
# bundle (.process("Resources")) as untracked noise.
#
# To promote a NEW snapshot to a doc image: run with COPY_ALL=1 (or copy it
# by hand from __Snapshots__/), then `git add` it. From then on it refreshes
# automatically. Set COPY_ALL=1 to copy every snapshot regardless of tracking.
RESOURCES_REL="Sources/KeyPathAppKit/Resources"
echo ""
echo "📋 Refreshing curated doc screenshots in Resources..."

COPIED=0
SKIPPED=0
for png in "$SNAPSHOTS_DIR"/*/*.png; do
    if [ -f "$png" ]; then
        BASENAME=$(basename "$png")
        # Snapshot files are named like: testFunctionName.screenshot-name.png
        # Extract just the screenshot name (after the first dot)
        SCREENSHOT_NAME="${BASENAME#*.}"
        if [ "$SCREENSHOT_NAME" != "$BASENAME" ] && [ -n "$SCREENSHOT_NAME" ]; then
            # Allow-list = already-tracked doc images (self-maintaining),
            # unless COPY_ALL=1 forces a full copy for discovery.
            if [ "${COPY_ALL:-0}" = "1" ] || \
               git -C "$PROJECT_DIR" ls-files --error-unmatch "$RESOURCES_REL/$SCREENSHOT_NAME" >/dev/null 2>&1; then
                cp "$png" "$RESOURCES_DIR/$SCREENSHOT_NAME"
                COPIED=$((COPIED + 1))
            else
                SKIPPED=$((SKIPPED + 1))
            fi
        fi
    fi
done

echo "✅ Refreshed $COPIED curated doc screenshots ($SKIPPED regression-only snapshots skipped)"

# -----------------------------------------------------------------------
# Step 3: Peekaboo system screenshots (optional)
# -----------------------------------------------------------------------
if [ "${SKIP_PEEKABOO:-0}" = "1" ]; then
    echo ""
    echo "⏭️  Skipping Peekaboo screenshots (SKIP_PEEKABOO=1)"
else
    if command -v peekaboo &>/dev/null; then
        echo ""
        echo "📷 Capturing Peekaboo system screenshots..."
        # Only capture the non-interactive ones (accessibility + input-monitoring)
        "$SCRIPT_DIR/capture-peekaboo-screenshots.sh" accessibility 2>&1 || {
            echo "⚠️  Peekaboo accessibility capture failed (non-fatal)"
        }
        "$SCRIPT_DIR/capture-peekaboo-screenshots.sh" input-monitoring 2>&1 || {
            echo "⚠️  Peekaboo input-monitoring capture failed (non-fatal)"
        }
        echo "✅ Peekaboo captures complete"
    else
        echo ""
        echo "⏭️  Peekaboo not installed, skipping system screenshots"
        echo "   Install with: brew install steipete/tap/peekaboo"
    fi
fi

echo ""
echo "📸 Screenshot regeneration complete!"
echo "   SwiftUI snapshots: $COPIED"
echo "   Resources dir: $RESOURCES_DIR"
