#!/bin/bash
# regenerate-screenshots.sh
#
# Regenerates all SwiftUI snapshot screenshots and copies them to Resources/
# for use in help documentation.
#
# This script:
#   1. Runs snapshot tests in RECORD mode (generates new reference PNGs)
#   2. Copies the generated PNGs from __Snapshots__/ to Resources/
#
# Usage:
#   ./Scripts/regenerate-screenshots.sh          # full regeneration
#   SKIP_PEEKABOO=1 ./Scripts/regenerate-screenshots.sh  # SwiftUI only
#
# Environment:
#   SKIP_PEEKABOO=1  - Skip Peekaboo system screenshots (requires app install + permissions)
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
# Step 2: Copy snapshot PNGs to Resources
# -----------------------------------------------------------------------
echo ""
echo "📋 Copying snapshots to Resources..."

COPIED=0
for png in "$SNAPSHOTS_DIR"/*/*.png; do
    if [ -f "$png" ]; then
        BASENAME=$(basename "$png")
        # Snapshot files are named like: testFunctionName.screenshot-name.png
        # Extract just the screenshot name (after the first dot)
        SCREENSHOT_NAME="${BASENAME#*.}"
        if [ "$SCREENSHOT_NAME" != "$BASENAME" ] && [ -n "$SCREENSHOT_NAME" ]; then
            cp "$png" "$RESOURCES_DIR/$SCREENSHOT_NAME"
            COPIED=$((COPIED + 1))
        fi
    fi
done

echo "✅ Copied $COPIED screenshots to $RESOURCES_DIR"

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
