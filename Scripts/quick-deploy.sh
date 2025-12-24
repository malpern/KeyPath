#!/bin/bash
# Quick deploy for development: build, copy to /Applications, restart
# No signing or notarization - just fast iteration (~3-4 seconds)
#
# Prerequisites: Run ./build.sh once to create the initial app bundle structure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
APP_NAME="KeyPath"
APP_BUNDLE="/Applications/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
ENTITLEMENTS="$PROJECT_DIR/KeyPath.entitlements"

cd "$PROJECT_DIR"

# Check prerequisites
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ App bundle not found at $APP_BUNDLE"
    echo "💡 Run './build.sh' once to create the initial app structure"
    exit 1
fi

# Build debug (fast - incremental)
echo "🔨 Building..."
swift build --product KeyPath 2>&1 | grep -v "^$" | tail -3

# Get the built binary
DEBUG_BIN=$(swift build --product KeyPath --show-bin-path)/KeyPath

if [[ ! -f "$DEBUG_BIN" ]]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi

# Copy binary to app bundle
echo "📦 Deploying..."
cp "$DEBUG_BIN" "$MACOS_DIR/$APP_NAME"

# Add the missing rpath for Sparkle framework (debug builds don't have this)
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Re-sign with entitlements (ad-hoc, fast)
echo "✍️  Signing..."
codesign --force --sign - --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null

# Restart the app
echo "🔄 Restarting..."
if pgrep -x "$APP_NAME" > /dev/null; then
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.3
fi

open "$APP_BUNDLE"
echo "✅ Done!"
