#!/bin/bash

# KeyPath Build Script
# Creates a proper macOS app bundle for KeyPath

set -e

echo "🦀 Building bundled kanata for development..."
# Build kanata from source with STABLE Developer ID signing
# CRITICAL: Never use ad-hoc signing - breaks TCC identity persistence
CODESIGN_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)" ./Scripts/build-kanata.sh

echo "🏗️  Building KeyPath..."
# Build the Swift package (disable whole-module optimization to avoid hang)
swift build -c release -Xswiftc -no-whole-module-optimization

# Create app bundle structure
APP_BUNDLE="build/KeyPath.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$CONTENTS_DIR/Library/KeyPath"

# Copy executable
cp .build/arm64-apple-macosx/release/KeyPath "$MACOS_DIR/KeyPath"

# Copy bundled kanata binary
cp build/kanata-universal "$CONTENTS_DIR/Library/KeyPath/kanata"

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

# REQUIRED: Sign with stable Developer ID for TCC persistence
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
if command -v codesign >/dev/null 2>&1; then
    echo "Signing app bundle with stable Developer ID..."
    # Sign kanata binary first for stable identity
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS_DIR/Library/KeyPath/kanata"
    
    # Sign main app bundle WITH entitlements
    ENTITLEMENTS_FILE="KeyPath.entitlements"
    if [ -f "$ENTITLEMENTS_FILE" ]; then
        echo "Applying entitlements from $ENTITLEMENTS_FILE..."
        codesign --force --options=runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    else
        echo "⚠️ WARNING: No entitlements file found - admin operations may fail"
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    fi
    echo "✅ Signed with stable identity for TCC persistence"
else
    echo "❌ ERROR: codesign not found - TCC will reset every build!"
    exit 1
fi

echo "App bundle created at: $APP_BUNDLE"
echo
echo "To run KeyPath:"
echo "  open $APP_BUNDLE"
echo
echo "To install the Kanata service:"
echo "  sudo ./install-system.sh"
echo
echo "✅ Build uses stable Developer ID - TCC permissions persist across builds"