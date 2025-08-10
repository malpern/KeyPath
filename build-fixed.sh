#!/bin/bash
set -e

# Configuration
APP_NAME="KeyPath"
BUNDLE_IDENTIFIER="com.keypath.KeyPath"
VERSION="1.0.0"
BUILD_TIME=$(date '+%m/%d %H:%M')

echo "Building KeyPath release version..."
echo "Build timestamp: $BUILD_TIME"

# Clean previous builds
rm -rf .build/release
rm -rf dist/${APP_NAME}.app

# Build the release version - this creates object files but not the executable
swift build -c release --product KeyPath

# Find the actual binary location (SPM puts it in architecture-specific directory)
BINARY_PATH=$(find .build -name "${APP_NAME}" -type f -perm +111 2>/dev/null | head -1)

# If no binary found, we need to link it manually
if [ -z "$BINARY_PATH" ]; then
    echo "Binary not found by SPM, linking manually..."
    
    # Find the build directory
    BUILD_DIR=".build/arm64-apple-macosx/release"
    
    # Link the executable from the object files
    swiftc -o "$BUILD_DIR/KeyPath" \
        -L "$BUILD_DIR" \
        -I "$BUILD_DIR" \
        "$BUILD_DIR/KeyPath.build/"*.swift.o \
        -framework SwiftUI \
        -framework AppKit \
        -framework Foundation \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
    
    BINARY_PATH="$BUILD_DIR/KeyPath"
fi

# Create app bundle in dist
echo "Creating app bundle..."
mkdir -p dist/${APP_NAME}.app/Contents/MacOS
mkdir -p dist/${APP_NAME}.app/Contents/Resources

# Copy built binary
if [ -f "$BINARY_PATH" ]; then
    cp "$BINARY_PATH" dist/${APP_NAME}.app/Contents/MacOS/${APP_NAME}
    echo "Binary copied from: $BINARY_PATH"
else
    echo "ERROR: Could not find or create binary!"
    exit 1
fi

# Copy icon if it exists
if [ -f Sources/KeyPath/Resources/AppIcon.icns ]; then
    cp Sources/KeyPath/Resources/AppIcon.icns dist/${APP_NAME}.app/Contents/Resources/
fi

# Create Info.plist with build timestamp
cat > dist/${APP_NAME}.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyPath</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>BuildTimestamp</key>
    <string>${BUILD_TIME}</string>
</dict>
</plist>
EOF

echo "App bundle created at dist/${APP_NAME}.app"
echo "Binary size: $(ls -lh dist/${APP_NAME}.app/Contents/MacOS/${APP_NAME} | awk '{print $5}')"
echo ""
echo "To install:"
echo "  cp -r dist/${APP_NAME}.app /Applications/"