#!/bin/bash

# KeyPath Build Script
# Creates a proper macOS app bundle for KeyPath

set -e

echo "Building KeyPath..."

# Build the Swift package
swift build -c release

# Create app bundle structure
APP_BUNDLE="build/KeyPath.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/arm64-apple-macosx/release/KeyPath "$MACOS_DIR/KeyPath"

# Copy app icon
if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
    cp "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
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
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

echo "App bundle created at: $APP_BUNDLE"
echo
echo "To run KeyPath:"
echo "  open $APP_BUNDLE"
echo
echo "To install the Kanata service:"
echo "  sudo ./install-system.sh"