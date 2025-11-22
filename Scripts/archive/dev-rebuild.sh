#!/bin/bash

# Development rebuild script that preserves permissions
# This keeps the same app bundle and just updates the binary

set -e

echo "Development rebuild (preserves permissions)..."

# Build the Swift package
swift build -c release

APP_BUNDLE="/Applications/KeyPath.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "KeyPath not installed, running full build..."
    ./Scripts/build-and-sign.sh
    exit 0
fi

echo "Updating existing app bundle to preserve permissions..."

# Kill any running instances
pkill -f KeyPath || true
sleep 1

# Just replace the binary, keeping the same bundle
cp .build/arm64-apple-macosx/release/KeyPath "$MACOS_DIR/KeyPath"

# Re-sign the updated binary to maintain code signature validity
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags --timestamp=none "$APP_BUNDLE" 2>/dev/null || {
    echo "Warning: Code signing failed, but binary updated"
}

echo "✅ KeyPath binary updated in place - permissions preserved!"
echo "Launching updated app..."
open "$APP_BUNDLE"