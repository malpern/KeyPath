#!/bin/bash

# Workaround build script for Swift 6.2 hang issue
# Uses simpler approach with fewer optimizations

set -e

echo "🔧 KeyPath Build Workaround"
echo "=========================="

# Clean if requested
if [[ "$1" == "--clean" ]]; then
    echo "Cleaning build artifacts..."
    rm -rf .build
fi

# Try building with minimal flags to avoid hangs
echo "Building with minimal configuration..."

# Use basic build command with timeout
timeout 120 swift build -c release --product KeyPath 2>&1 | tee build-workaround.log &
BUILD_PID=$!

# Monitor the build
COUNTER=0
while kill -0 $BUILD_PID 2>/dev/null; do
    if [ $COUNTER -lt 120 ]; then
        if [ $((COUNTER % 10)) -eq 0 ]; then
            echo "Building... ($COUNTER seconds)"
        fi
        sleep 1
        ((COUNTER++))
    else
        echo "Build timed out after 120 seconds"
        kill -9 $BUILD_PID 2>/dev/null
        break
    fi
done

wait $BUILD_PID 2>/dev/null
BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ] || [ $BUILD_RESULT -eq 124 ]; then
    echo "Checking for built executable..."
    
    EXEC_PATH=".build/arm64-apple-macosx/release/KeyPath"
    
    if [ -f "$EXEC_PATH" ]; then
        echo "✅ Found executable at: $EXEC_PATH"
        
        # Create minimal app bundle
        APP_BUNDLE="build/KeyPath.app"
        rm -rf "$APP_BUNDLE"
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        mkdir -p "$APP_BUNDLE/Contents/Resources"
        
        cp "$EXEC_PATH" "$APP_BUNDLE/Contents/MacOS/KeyPath"
        
        # Create minimal Info.plist
        cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyPath</string>
    <key>CFBundleIdentifier</key>
    <string>com.keypath.KeyPath</string>
    <key>CFBundleName</key>
    <string>KeyPath</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF
        
        # Copy icon if available
        if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
            cp "Sources/KeyPath/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
        fi
        
        echo "✅ App bundle created at: $APP_BUNDLE"
        echo ""
        echo "To install: sudo cp -r $APP_BUNDLE /Applications/"
    else
        echo "❌ Executable not found. Build may have failed."
        echo "Checking build directory..."
        find .build -name "KeyPath" -type f 2>/dev/null | head -5
    fi
else
    echo "❌ Build failed with exit code: $BUILD_RESULT"
fi