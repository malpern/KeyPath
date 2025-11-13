#!/bin/bash
# Deploy the already-packaged dist/KeyPath.app to /Applications without rebuilding.
set -euo pipefail

DIST_APP="dist/KeyPath.app"
TARGET="/Applications/KeyPath.app"

if [ ! -d "$DIST_APP" ]; then
    echo "❌ dist/KeyPath.app not found. Run ./build.sh first so the app bundle includes HelperTools and LaunchDaemons." >&2
    exit 1
fi

verify_dist_bundle() {
    local helper="$DIST_APP/Contents/Library/HelperTools/KeyPathHelper"
    local helper_plist="$DIST_APP/Contents/Library/LaunchDaemons/com.keypath.helper.plist"
    local kanata_plist="$DIST_APP/Contents/Library/LaunchDaemons/com.keypath.kanata.plist"
    for path in "$helper" "$helper_plist" "$kanata_plist"; do
        if [ ! -e "$path" ]; then
            echo "❌ dist bundle missing required asset: $path" >&2
            echo "💡 Re-run ./build.sh to regenerate a complete app bundle before deploying." >&2
            exit 1
        fi
    done
}

verify_dist_bundle

echo "🛑 Stopping running KeyPath (best effort)..."
osascript -e 'tell application "KeyPath" to quit' >/dev/null 2>&1 || true
pkill -f "/KeyPath.app/Contents/MacOS/KeyPath" >/dev/null 2>&1 || true

echo "🧹 Removing old copy at $TARGET..."
sudo rm -rf "$TARGET"

echo "🚀 Deploying $DIST_APP -> $TARGET"
sudo ditto "$DIST_APP" "$TARGET"

echo "✅ Deployment complete." 
echo "To relaunch: open $TARGET"
