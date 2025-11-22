#!/bin/bash

# Live development mode - watches for changes and rebuilds automatically
# Preserves permissions by updating the binary in-place

set -e

APP_BUNDLE="/Applications/KeyPath.app"
WATCH_DIRS="Sources/ Package.swift"

echo "🔄 Live development mode starting..."
echo "Watching: $WATCH_DIRS"
echo "Target: $APP_BUNDLE"
echo ""

# Initial build
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Creating initial signed build..."
    ./build-and-sign.sh
else
    echo "Updating existing build..."
    ./dev-rebuild.sh
fi

echo ""
echo "👀 Watching for changes... (Press Ctrl+C to stop)"

# Watch for changes and rebuild
fswatch -o $WATCH_DIRS | while read f; do
    echo ""
    echo "📝 Changes detected, rebuilding..."
    
    # Kill app if running
    pkill -f KeyPath || true
    sleep 0.5
    
    # Quick rebuild
    if swift build -c release 2>/dev/null; then
        cp .build/arm64-apple-macosx/release/KeyPath "$APP_BUNDLE/Contents/MacOS/KeyPath"
        codesign --force --sign - --preserve-metadata=identifier,entitlements,flags --timestamp=none "$APP_BUNDLE" 2>/dev/null || true
        
        echo "✅ Rebuilt and updated!"
        echo "🚀 Launching..."
        open "$APP_BUNDLE"
    else
        echo "❌ Build failed, check your code"
    fi
    
    echo "👀 Watching for changes..."
done