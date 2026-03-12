#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -e  # Exit on any error

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
source "$SCRIPT_DIR/lib/signing.sh"

# Function to create Sparkle update archive with EdDSA signature.
#
# Defined near the top so it can be invoked from the main build flow below.
create_sparkle_archive() {
    echo ""
    echo "✨ Creating Sparkle update archive..."

    # Extract version from Info.plist
    local VERSION
    VERSION=$(defaults read "$CONTENTS/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
    local BUILD
    BUILD=$(defaults read "$CONTENTS/Info" CFBundleVersion 2>/dev/null || echo "1")
    local ARCHIVE_NAME="KeyPath-${VERSION}.zip"
    local SPARKLE_DIR="${DIST_DIR}/sparkle"

    mkdir -p "$SPARKLE_DIR"

    # Create versioned ZIP for Sparkle (separate from the notarization zip)
    echo "📦 Creating versioned archive: $ARCHIVE_NAME"
    cd "$DIST_DIR"
    ditto -c -k --keepParent "${APP_NAME}.app" "sparkle/${ARCHIVE_NAME}"
    cd ..

    # Sign with EdDSA using Sparkle's sign_update tool.
    # Resolve dynamically because Homebrew cask versions change frequently.
    local SIGN_UPDATE=""
    local SIGNATURE=""
    if command -v sign_update >/dev/null 2>&1; then
        SIGN_UPDATE="$(command -v sign_update)"
    else
        local CASK_VERSION=""
        CASK_VERSION="$(brew list --cask --versions sparkle 2>/dev/null | awk '{print $2}')"
        for CASK_ROOT in /opt/homebrew/Caskroom/sparkle /usr/local/Caskroom/sparkle; do
            if [ -n "$CASK_VERSION" ] && [ -x "$CASK_ROOT/$CASK_VERSION/bin/sign_update" ]; then
                SIGN_UPDATE="$CASK_ROOT/$CASK_VERSION/bin/sign_update"
                break
            fi
        done

        # Fallback: pick the newest installed sign_update in known cask roots.
        if [ -z "$SIGN_UPDATE" ]; then
            local CANDIDATE=""
            for CASK_ROOT in /opt/homebrew/Caskroom/sparkle /usr/local/Caskroom/sparkle; do
                CANDIDATE="$(ls -1dt "$CASK_ROOT"/*/bin/sign_update 2>/dev/null | head -n1 || true)"
                if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
                    SIGN_UPDATE="$CANDIDATE"
                    break
                fi
            done
        fi
    fi

    if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
        echo "🔎 Using sign_update at: $SIGN_UPDATE"
        echo "🔐 Signing archive with EdDSA..."

        # sign_update typically prints: sparkle:edSignature="BASE64..."
        # Normalize so SIGNATURE is just the base64 payload (not the full attribute string).
        local SIGN_OUTPUT
        SIGN_OUTPUT=$("$SIGN_UPDATE" "${SPARKLE_DIR}/${ARCHIVE_NAME}" 2>/dev/null || echo "")
        SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
        if [ -z "$SIGNATURE" ]; then
            # Some versions may print just the signature string; accept that form too.
            SIGNATURE=$(echo "$SIGN_OUTPUT" | tr -d '\n' | tr -d '\r')
        fi

        if [ -n "$SIGNATURE" ]; then
            echo "$SIGNATURE" > "${SPARKLE_DIR}/${ARCHIVE_NAME}.sig"
            echo "✅ EdDSA signature generated"
        else
            echo "⚠️ WARNING: EdDSA signing failed - check Keychain for Sparkle key"
        fi
    else
        echo "⚠️ WARNING: sign_update not found in PATH or Homebrew Caskroom"
        echo "   Install Sparkle CLI tools and ensure sign_update is available on PATH."
    fi

    if [ -z "$SIGNATURE" ]; then
        if [ "${ALLOW_UNSIGNED_SPARKLE:-0}" = "1" ]; then
            echo "⚠️ WARNING: Continuing without Sparkle EdDSA signature (ALLOW_UNSIGNED_SPARKLE=1)"
        else
            echo "❌ ERROR: Missing Sparkle EdDSA signature; aborting release archive generation." >&2
            echo "   Ensure sign_update is installed and your Sparkle private key is available in Keychain." >&2
            echo "   Set ALLOW_UNSIGNED_SPARKLE=1 only for local testing." >&2
            return 1
        fi
    fi

    # Get file size
    local SIZE
    SIZE=$(stat -f '%z' "${SPARKLE_DIR}/${ARCHIVE_NAME}" 2>/dev/null || stat --format='%s' "${SPARKLE_DIR}/${ARCHIVE_NAME}" 2>/dev/null || echo "0")
    local PUB_DATE
    PUB_DATE=$(date -R 2>/dev/null || date '+%a, %d %b %Y %T %z')

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
        https://github.com/malpern/KeyPath/releases/tag/v${VERSION}
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

echo "🦀 Building bundled kanata..."
# Build kanata from source (required for proper signing)
./Scripts/build-kanata.sh

echo "🔬 Building kanata simulator..."
# Build simulator for dry-run simulation
./Scripts/build-kanata-simulator.sh

echo "🧩 Building kanata host bridge..."
./Scripts/build-kanata-host-bridge.sh

echo "🔐 Building privileged helper..."
# Build and sign the helper tool
./Scripts/build-helper.sh

# Screenshot regeneration + website publish only run for full release builds.
# Skipped when SKIP_NOTARIZE=1 (dev builds via `dd`).
if [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo "📸 Regenerating help screenshots..."
    SKIP_PEEKABOO="${SKIP_PEEKABOO:-1}" ./Scripts/regenerate-screenshots.sh
else
    echo "⏭️  Skipping screenshot regeneration (dev build)"
fi

echo "🏗️  Building KeyPath and plugins..."
# Build main app + insights plugin (KeyPathPluginKit is statically linked, no separate dylib needed)
# Note: `swift build` accepts a single `--product`; passing it twice can skip the first one.
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization
swift build --configuration release --product KeyPathKanataLauncher -Xswiftc -no-whole-module-optimization
swift build --configuration release --product KeyPathOutputBridge -Xswiftc -no-whole-module-optimization
swift build --configuration release --product KeyPathInsights -Xswiftc -no-whole-module-optimization

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

	# Ensure app-bundle rpath can locate embedded frameworks
	# SwiftPM-built executables usually have LC_RPATH=@loader_path, which points to Contents/MacOS.
	# For an app bundle, frameworks live at Contents/Frameworks, so add that search path.
	install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/KeyPath" 2>/dev/null || true

	# Create KanataEngine.app bundle wrapping the kanata binary.
	# This gives kanata a CFBundleIdentifier so macOS TCC tracks it by bundle ID
	# (client_type=0) instead of raw path (client_type=1), which ensures it appears
	# in System Settings on macOS Tahoe 26.1+ and survives path changes.
	KANATA_ENGINE_APP="$CONTENTS/Library/KeyPath/KanataEngine.app"
	KANATA_ENGINE_CONTENTS="$KANATA_ENGINE_APP/Contents"
	KANATA_ENGINE_MACOS="$KANATA_ENGINE_CONTENTS/MacOS"
	mkdir -p "$KANATA_ENGINE_MACOS"

	# Move kanata binary into the .app bundle
	ditto "build/kanata-universal" "$KANATA_ENGINE_MACOS/kanata"

	# Copy committed Info.plist for KanataEngine.app
	cp "$SCRIPT_DIR/../Sources/KeyPathApp/Resources/KanataEngine-Info.plist" "$KANATA_ENGINE_CONTENTS/Info.plist"

	# Inject the main app's version into KanataEngine.app so the bundle version
	# stays in sync across releases (the source plist uses placeholder values).
	_MAIN_VER=$(defaults read "$SCRIPT_DIR/../Sources/KeyPathApp/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
	_MAIN_BUILD=$(defaults read "$SCRIPT_DIR/../Sources/KeyPathApp/Info" CFBundleVersion 2>/dev/null || echo "1")
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $_MAIN_VER" "$KANATA_ENGINE_CONTENTS/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $_MAIN_BUILD" "$KANATA_ENGINE_CONTENTS/Info.plist"

	# Create backward-compat symlink so existing code paths still resolve
	ln -sf "KanataEngine.app/Contents/MacOS/kanata" "$CONTENTS/Library/KeyPath/kanata"

	# Copy bundled kanata simulator binary
	ditto "build/kanata-simulator" "$CONTENTS/Library/KeyPath/kanata-simulator"

	# Copy bundled host bridge library used for in-process smoke checks and future runtime hosting
	ditto "build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib" "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"

	# Embed Sparkle.framework (required at runtime for updates; otherwise dyld aborts at launch)
	SPARKLE_FRAMEWORK_SRC="$BUILD_DIR/Sparkle.framework"
	if [ -d "$SPARKLE_FRAMEWORK_SRC" ]; then
	    ditto "$SPARKLE_FRAMEWORK_SRC" "$FRAMEWORKS/Sparkle.framework"
	else
	    echo "❌ ERROR: Sparkle.framework not found at $SPARKLE_FRAMEWORK_SRC" >&2
	    echo "   This usually indicates the Sparkle SPM dependency did not build." >&2
	    exit 1
	fi

	# Assemble Insights plugin bundle
	echo "🔌 Assembling Insights.bundle..."
	PLUGINS_DIR="$CONTENTS/PlugIns"
	INSIGHTS_BUNDLE="$PLUGINS_DIR/Insights.bundle"
	INSIGHTS_CONTENTS="$INSIGHTS_BUNDLE/Contents"
	INSIGHTS_MACOS="$INSIGHTS_CONTENTS/MacOS"
	mkdir -p "$INSIGHTS_MACOS"

	INSIGHTS_DYLIB="$BUILD_DIR/libKeyPathInsights.dylib"
	if [ -f "$INSIGHTS_DYLIB" ]; then
	    ditto "$INSIGHTS_DYLIB" "$INSIGHTS_MACOS/libKeyPathInsights"
	    ditto "Sources/KeyPathInsights/Info.plist" "$INSIGHTS_CONTENTS/Info.plist"
	    echo "✅ Assembled Insights.bundle"
	else
	    echo "❌ ERROR: libKeyPathInsights.dylib not found at $INSIGHTS_DYLIB" >&2
	    exit 1
	fi

		# Copy the bundled runtime host executable used by SMAppService
		KANATA_LAUNCHER_SRC="$BUILD_DIR/KeyPathKanataLauncher"
		KANATA_LAUNCHER_DST="$CONTENTS/Library/KeyPath/kanata-launcher"
		ditto "$KANATA_LAUNCHER_SRC" "$KANATA_LAUNCHER_DST"
		chmod 755 "$KANATA_LAUNCHER_DST"

# Embed privileged helper for SMJobBless
echo "📦 Embedding privileged helper (SMAppService layout)..."
HELPER_TOOLS="$CONTENTS/Library/HelperTools"
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"
mkdir -p "$HELPER_TOOLS" "$LAUNCH_DAEMONS"

# Copy helper binary into Contents/Library/HelperTools/
ditto "$BUILD_DIR/KeyPathHelper" "$HELPER_TOOLS/KeyPathHelper"
ditto "$BUILD_DIR/KeyPathOutputBridge" "$HELPER_TOOLS/KeyPathOutputBridge"

# Copy daemon plist into bundle-local LaunchDaemons with final name
ditto "Sources/KeyPathHelper/com.keypath.helper.plist" "$LAUNCH_DAEMONS/com.keypath.helper.plist"
ditto "Sources/KeyPathOutputBridge/com.keypath.output-bridge.plist" "$LAUNCH_DAEMONS/com.keypath.output-bridge.plist"

# Copy Kanata daemon plist for SMAppService
ditto "Sources/KeyPathApp/com.keypath.kanata.plist" "$LAUNCH_DAEMONS/com.keypath.kanata.plist"

	verify_embedded_artifacts() {
	    local missing=0
	    for path in \
	        "$HELPER_TOOLS/KeyPathHelper" \
	        "$HELPER_TOOLS/KeyPathOutputBridge" \
	        "$LAUNCH_DAEMONS/com.keypath.helper.plist" \
	        "$LAUNCH_DAEMONS/com.keypath.output-bridge.plist" \
	        "$LAUNCH_DAEMONS/com.keypath.kanata.plist" \
	        "$FRAMEWORKS/Sparkle.framework" \
	        "$INSIGHTS_BUNDLE/Contents/MacOS/libKeyPathInsights" \
	        "$INSIGHTS_BUNDLE/Contents/Info.plist" \
	        "$KANATA_LAUNCHER_DST" \
	        "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" \
	        "$CONTENTS/Library/KeyPath/kanata-simulator" \
	        "$CONTENTS/Library/KeyPath/KanataEngine.app/Contents/MacOS/kanata" \
	        "$CONTENTS/Library/KeyPath/KanataEngine.app/Contents/Info.plist"; do
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

echo "✅ Helper embedded: $HELPER_TOOLS/KeyPathHelper"
echo "✅ Output bridge embedded: $HELPER_TOOLS/KeyPathOutputBridge"
echo "✅ Helper plist embedded: $LAUNCH_DAEMONS/com.keypath.helper.plist"
echo "✅ Output bridge plist embedded: $LAUNCH_DAEMONS/com.keypath.output-bridge.plist"
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

# Copy SwiftPM resource bundles (KeyPath_KeyPath.bundle, KeyPath_KeyPathAppKit.bundle, etc.)
for RESOURCE_BUNDLE in "$BUILD_DIR"/KeyPath_*.bundle; do
    if [ -d "$RESOURCE_BUNDLE" ]; then
        BUNDLE_NAME=$(basename "$RESOURCE_BUNDLE")
        ditto "$RESOURCE_BUNDLE" "$RESOURCES/$BUNDLE_NAME"
        echo "✅ Copied resource bundle: $BUNDLE_NAME"
    fi
done

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

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"

if [ "$SKIP_CODESIGN" = "1" ]; then
    echo "⏭️  Skipping codesign (SKIP_CODESIGN=1)"
    SKIP_NOTARIZE=1
else
    echo "✍️  Signing executables..."
    if [ "${KP_SIGN_DRY_RUN:-0}" != "1" ]; then
        if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
            echo "❌ ERROR: codesign identity not found: $SIGNING_IDENTITY" >&2
            echo "Available identities:" >&2
            security find-identity -v -p codesigning >&2 || true
            echo "💡 TIP: Set CODESIGN_IDENTITY to a valid Developer ID Application identity." >&2
            exit 1
        fi
    fi

    # Sign from innermost to outermost (helper -> kanata -> main app)

    # Sign privileged helper (bundle-local binary)
    HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"
    kp_sign "$HELPER_TOOLS/KeyPathHelper" \
        --force --options=runtime \
        --identifier "com.keypath.helper" \
        --entitlements "$HELPER_ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY"

    OUTPUT_BRIDGE_ENTITLEMENTS="Sources/KeyPathOutputBridge/KeyPathOutputBridge.entitlements"
    kp_sign "$HELPER_TOOLS/KeyPathOutputBridge" \
        --force --options=runtime \
        --identifier "com.keypath.output-bridge" \
        --entitlements "$OUTPUT_BRIDGE_ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY"

    # Sign KanataEngine.app bundle inside-out: sign the inner binary first, then the bundle.
    kp_sign "$CONTENTS/Library/KeyPath/KanataEngine.app/Contents/MacOS/kanata" --force --options=runtime --sign "$SIGNING_IDENTITY"
    kp_sign "$CONTENTS/Library/KeyPath/KanataEngine.app" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign the bundled runtime host pieces explicitly before the outer app sign.
    kp_sign "$CONTENTS/Library/KeyPath/kanata-launcher" --force --options=runtime --sign "$SIGNING_IDENTITY"
    kp_sign "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign bundled kanata simulator binary
    kp_sign "$CONTENTS/Library/KeyPath/kanata-simulator" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign Insights plugin bundle
    kp_sign "$INSIGHTS_BUNDLE" --force --options=runtime --deep --sign "$SIGNING_IDENTITY"

    # Sign embedded Sparkle framework (contains nested helper apps; deep signing is simplest)
    kp_sign "$FRAMEWORKS/Sparkle.framework" --force --options=runtime --deep --sign "$SIGNING_IDENTITY"

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
fi

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

# ─────────────────────────────────────────────────────────────────────
# Publish help content to website
# ─────────────────────────────────────────────────────────────────────

GHPAGES_DIR="$SCRIPT_DIR/../.worktrees/gh-pages"
if [ -d "$GHPAGES_DIR" ] && [ "${SKIP_WEBSITE:-0}" != "1" ] && [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo ""
    echo "🌐 Publishing help content to website..."
    "$SCRIPT_DIR/publish-help-to-web.sh"

    echo ""
    echo "🌐 Committing and pushing gh-pages..."
    cd "$GHPAGES_DIR"
    if git diff --quiet && git diff --cached --quiet; then
        echo "   No website changes to commit"
    else
        git add -A
        git commit -m "Sync help docs from app ($(date '+%Y-%m-%d'))"
        git push origin gh-pages
        echo "   ✅ Website published"
    fi
    cd "$SCRIPT_DIR/.."
else
    if [ "${SKIP_WEBSITE:-0}" = "1" ]; then
        echo "⏭️  Skipping website publish (SKIP_WEBSITE=1)"
    fi
fi
