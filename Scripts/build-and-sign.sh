#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -e  # Exit on any error

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
source "$SCRIPT_DIR/lib/signing.sh"

echo "🦀 Building bundled kanata..."
# Build kanata from source (required for proper signing)
./Scripts/build-kanata.sh

echo "🔬 Building kanata simulator..."
# Build simulator for dry-run simulation
./Scripts/build-kanata-simulator.sh

echo "🔐 Building privileged helper..."
# Build and sign the helper tool
./Scripts/build-helper.sh

echo "🏗️  Building KeyPath..."
# Build main app (disable whole-module optimization to avoid hang)
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization

echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

# Clean and create directories
rm -rf "$DIST_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"
mkdir -p "$CONTENTS/Library/KeyPath"

# Copy main executable
ditto "$BUILD_DIR/KeyPath" "$MACOS/KeyPath"

# Copy bundled kanata binary
ditto "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"

# Copy bundled kanata simulator binary
ditto "build/kanata-simulator" "$CONTENTS/Library/KeyPath/kanata-simulator"

# Copy kanata launcher script to enforce absolute config paths
KANATA_LAUNCHER_SRC="Scripts/kanata-launcher.sh"
KANATA_LAUNCHER_DST="$CONTENTS/Library/KeyPath/kanata-launcher"
ditto "$KANATA_LAUNCHER_SRC" "$KANATA_LAUNCHER_DST"
chmod 755 "$KANATA_LAUNCHER_DST"

# Embed privileged helper for SMAppService
echo "📦 Embedding privileged helper (SMAppService layout)..."
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"
mkdir -p "$LAUNCH_DAEMONS"

# Copy helper binary into Contents/MacOS (required for SMAppService daemons)
# Note: Contents/MacOS is the correct location for SMAppService BundleProgram
ditto "$BUILD_DIR/KeyPathHelper" "$MACOS/KeyPathHelper"

# Copy daemon plist into bundle-local LaunchDaemons with final name
ditto "Sources/KeyPathHelper/com.keypath.helper.plist" "$LAUNCH_DAEMONS/com.keypath.helper.plist"

# Copy Kanata daemon plist for SMAppService
ditto "Sources/KeyPathApp/com.keypath.kanata.plist" "$LAUNCH_DAEMONS/com.keypath.kanata.plist"

verify_embedded_artifacts() {
    local missing=0
    for path in \
        "$MACOS/KeyPathHelper" \
        "$LAUNCH_DAEMONS/com.keypath.helper.plist" \
        "$LAUNCH_DAEMONS/com.keypath.kanata.plist" \
        "$KANATA_LAUNCHER_DST" \
        "$CONTENTS/Library/KeyPath/kanata-simulator"; do
        if [ ! -e "$path" ]; then
            echo "❌ ERROR: Missing packaged artifact: $path" >&2
            missing=1
        fi
    done

    if [ $missing -ne 0 ]; then
        echo "💥 Packaging aborted because helper assets are incomplete." >&2
        exit 1
    fi
}

verify_embedded_artifacts
./Scripts/verify-kanata-plist.sh "$APP_BUNDLE"

echo "✅ Helper embedded: $MACOS/KeyPathHelper"
echo "✅ Helper plist embedded: $LAUNCH_DAEMONS/com.keypath.helper.plist"
echo "✅ Kanata daemon plist embedded: $LAUNCH_DAEMONS/com.keypath.kanata.plist"

# Copy main app Info.plist
ditto "Sources/KeyPathApp/Info.plist" "$CONTENTS/Info.plist"

# Copy bundled app resources (icons, helper scripts, etc.)
if [ -d "Sources/KeyPathApp/Resources" ]; then
    ditto "Sources/KeyPathApp/Resources/" "$RESOURCES"
    if [ -f "$RESOURCES/uninstall.sh" ]; then
        chmod 755 "$RESOURCES/uninstall.sh"
    fi
    echo "✅ Copied app resources"
else
    echo "⚠️ WARNING: Sources/KeyPath/Resources directory not found"
fi

# Embed Sparkle.framework (required at runtime)
SPARKLE_SRC=".build/arm64-apple-macosx/release/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    echo "📦 Embedding Sparkle.framework..."
    ditto "$SPARKLE_SRC" "$FRAMEWORKS/Sparkle.framework"
    # Provide @rpath compatibility for binaries expecting Sparkle next to executable
    ln -sf "../Frameworks/Sparkle.framework" "$MACOS/Sparkle.framework"
else
    echo "❌ ERROR: Sparkle.framework not found at $SPARKLE_SRC" >&2
    exit 1
fi

# Create PkgInfo file (required for app bundles)
echo "APPL????" > "$CONTENTS/PkgInfo"

# Create BuildInfo.plist for About dialog
echo "🧾 Writing BuildInfo.plist..."
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CFVER=$(defaults read "$CONTENTS/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
CFBUILD=$(defaults read "$CONTENTS/Info" CFBundleVersion 2>/dev/null || echo "0")
cat > "$RESOURCES/BuildInfo.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>${CFVER}</string>
  <key>CFBundleVersion</key>
  <string>${CFBUILD}</string>
  <key>GitCommit</key>
  <string>${GIT_HASH}</string>
  <key>BuildDate</key>
  <string>${BUILD_DATE}</string>
</dict>
</plist>
EOF

echo "✍️  Signing executables..."
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"

# Sign from innermost to outermost (helper -> kanata -> main app)

# Sign privileged helper (in Contents/MacOS)
HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"
kp_sign "$MACOS/KeyPathHelper" \
    --force --options=runtime \
    --identifier "com.keypath.helper" \
    --entitlements "$HELPER_ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY"

# Sign bundled kanata binary (already signed in build-kanata.sh, but ensure consistency)
kp_sign "$CONTENTS/Library/KeyPath/kanata" --force --options=runtime --sign "$SIGNING_IDENTITY"

# Sign bundled kanata simulator binary
kp_sign "$CONTENTS/Library/KeyPath/kanata-simulator" --force --options=runtime --sign "$SIGNING_IDENTITY"

# Sign embedded Sparkle binaries (inner → outer)
SPARKLE_BINS=(
    "$FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/Sparkle"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
)
for bin in "${SPARKLE_BINS[@]}"; do
    if [ -f "$bin" ]; then
        kp_sign "$bin" --force --options=runtime --timestamp --sign "$SIGNING_IDENTITY"
    else
        echo "⚠️ WARNING: Sparkle binary missing: $bin"
    fi
done

SPARKLE_CONTAINERS=(
    "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app"
    "$FRAMEWORKS/Sparkle.framework"
)
for bundle in "${SPARKLE_CONTAINERS[@]}"; do
    if [ -e "$bundle" ]; then
        kp_sign "$bundle" --force --options=runtime --timestamp --sign "$SIGNING_IDENTITY"
    else
        echo "⚠️ WARNING: Sparkle container missing: $bundle"
    fi
done

# Sign main app WITH entitlements
ENTITLEMENTS_FILE="KeyPath.entitlements"
if [ -f "$ENTITLEMENTS_FILE" ]; then
    echo "Applying entitlements from $ENTITLEMENTS_FILE..."
    kp_sign "$APP_BUNDLE" --force --options=runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY"
else
    echo "⚠️ WARNING: No entitlements file found - admin operations may fail"
    kp_sign "$APP_BUNDLE" --force --options=runtime --sign "$SIGNING_IDENTITY"
fi

echo "✅ Verifying signatures..."
kp_verify_signature "$APP_BUNDLE"

# Function to create Sparkle update archive with EdDSA signature
create_sparkle_archive() {
    echo ""
    echo "✨ Creating Sparkle update archive..."

    # Extract version from Info.plist (use PlistBuddy to avoid defaults path issues)
    local VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS/Info.plist" 2>/dev/null || echo "1.0.0")
    local BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CONTENTS/Info.plist" 2>/dev/null || echo "1")
    local ARCHIVE_NAME="KeyPath-${VERSION}.zip"
    local SPARKLE_DIR="${DIST_DIR}/sparkle"

    mkdir -p "$SPARKLE_DIR"

    # Create versioned ZIP for Sparkle (separate from the notarization zip)
    echo "📦 Creating versioned archive: $ARCHIVE_NAME"
    cd "$DIST_DIR"
    ditto -c -k --keepParent "${APP_NAME}.app" "sparkle/${ARCHIVE_NAME}"
    cd ..

    # Sign with EdDSA using Sparkle's sign_update tool
    local SIGN_UPDATE="/opt/homebrew/Caskroom/sparkle/2.8.1/bin/sign_update"
    local SIGNATURE=""
    if [ -x "$SIGN_UPDATE" ]; then
        echo "🔐 Signing archive with EdDSA..."
        # sign_update emits: sparkle:edSignature=\"<sig>\" length=\"<bytes>\"
        SIGNATURE=$("$SIGN_UPDATE" "${SPARKLE_DIR}/${ARCHIVE_NAME}" 2>/dev/null | awk -F'\"' '/sparkle:edSignature/ {print $2}')

        if [ -n "$SIGNATURE" ]; then
            echo "$SIGNATURE" > "${SPARKLE_DIR}/${ARCHIVE_NAME}.sig"
            echo "✅ EdDSA signature generated"
        else
            echo "⚠️ WARNING: EdDSA signing failed - check Keychain for Sparkle key"
        fi
    else
        echo "⚠️ WARNING: sign_update not found at $SIGN_UPDATE"
        echo "   Install with: brew install sparkle"
    fi

    # Get file size (wc -c is portable across macOS/Linux)
    local SIZE=$(wc -c < "${SPARKLE_DIR}/${ARCHIVE_NAME}" | tr -d ' ')
    local PUB_DATE=$(date -R)

    # Generate appcast entry XML
    echo "📝 Generating appcast entry..."
    cat > "${SPARKLE_DIR}/${ARCHIVE_NAME}.appcast-entry.xml" <<EOF
<!-- Add this item to appcast.xml -->
<item>
    <title>Version ${VERSION}</title>
    <sparkle:version>${BUILD}</sparkle:version>
    <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    <pubDate>${PUB_DATE}</pubDate>
    <enclosure
        url="https://github.com/malpern/KeyPath/releases/download/v${VERSION}/${ARCHIVE_NAME}"
        sparkle:edSignature="${SIGNATURE}"
        length="${SIZE}"
        type="application/octet-stream"/>
    <sparkle:releaseNotesLink>
        https://malpern.github.io/KeyPath/releases/${VERSION}.html
    </sparkle:releaseNotesLink>
</item>
EOF

    echo ""
    echo "✅ Sparkle archive created:"
    echo "   📦 Archive: ${SPARKLE_DIR}/${ARCHIVE_NAME}"
    echo "   🔐 Signature: ${SPARKLE_DIR}/${ARCHIVE_NAME}.sig"
    echo "   📝 Appcast entry: ${SPARKLE_DIR}/${ARCHIVE_NAME}.appcast-entry.xml"
    echo ""
    echo "📋 Next steps for release:"
    echo "   1. Upload ${ARCHIVE_NAME} to GitHub Releases as v${VERSION}"
    echo "   2. Copy appcast entry to appcast.xml"
    echo "   3. Commit and push appcast.xml"
}

if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
    echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)"
    echo "🎉 Build complete!"
    echo "📍 Signed app: $APP_BUNDLE"
else
    echo "📦 Creating distribution archive..."
    cd "$DIST_DIR"
    ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
    cd ..

    echo "📋 Submitting for notarization..."
    NOTARY_PROFILE="${NOTARY_PROFILE:-KeyPath-Profile}"
    kp_notarize_zip "${DIST_DIR}/${APP_NAME}.zip" "$NOTARY_PROFILE"

    echo "🔖 Stapling notarization..."
    kp_staple "$APP_BUNDLE"

    echo "🎉 Build complete!"
    echo "📍 Signed app: $APP_BUNDLE"
    echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

    echo "🔍 Final verification..."
    kp_spctl_assess "$APP_BUNDLE"

    echo "✨ Ready for distribution!"

    # Create Sparkle-compatible versioned archive
    create_sparkle_archive
fi

echo "📂 Deploying to /Applications..."
SYSTEM_APPS_DIR="/Applications"
APP_DEST="$SYSTEM_APPS_DIR/${APP_NAME}.app"
rm -rf "$APP_DEST"
if ditto "$APP_BUNDLE" "$APP_DEST"; then
    echo "✅ Deployed latest $APP_NAME to $APP_DEST"
else
    echo "⚠️ WARNING: Failed to copy $APP_NAME to $APP_DEST" >&2
    echo "💡 TIP: You may need to manually copy dist/${APP_NAME}.app to /Applications/" >&2
fi

echo "🚪 Restarting app..."

# Force quit old app process and wait for it to actually die
if pgrep -x "KeyPath" > /dev/null; then
    echo "   Stopping existing KeyPath process..."
    killall KeyPath 2>/dev/null || true

    # Wait up to 5 seconds for process to die
    for i in {1..10}; do
        if ! pgrep -x "KeyPath" > /dev/null; then
            break
        fi
        sleep 0.5
    done

    # Force kill if still running
    if pgrep -x "KeyPath" > /dev/null; then
        echo "   ⚠️  Process still running, force killing..."
        killall -9 KeyPath 2>/dev/null || true
        sleep 1
    fi
fi

# Verify no KeyPath process remains
if pgrep -x "KeyPath" > /dev/null; then
    echo "   ❌ ERROR: Failed to stop KeyPath process" >&2
    echo "   Please manually quit KeyPath and run: open $APP_DEST" >&2
    exit 1
fi

echo "   Starting new KeyPath..."
open "$APP_DEST"

# Wait for new process to start and verify
sleep 2
if pgrep -x "KeyPath" > /dev/null; then
    NEW_PID=$(pgrep -x "KeyPath")
    echo "   ✅ KeyPath restarted successfully (PID: $NEW_PID)"
else
    echo "   ⚠️  WARNING: KeyPath may not have started. Run manually: open $APP_DEST" >&2
fi
