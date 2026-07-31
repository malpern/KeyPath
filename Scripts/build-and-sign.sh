#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app.
# Set SKIP_DEPLOY=1 to leave the assembled candidate in dist/ without touching
# the currently installed app or its running keyboard service.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
source "$SCRIPT_DIR/lib/xcode.sh"
source "$SCRIPT_DIR/lib/signing.sh"
source "$SCRIPT_DIR/lib/deploy-lock.sh"
source "$SCRIPT_DIR/lib/deploy-app.sh"
source "$SCRIPT_DIR/lib/submodules.sh"
source "$SCRIPT_DIR/lib/sparkle.sh"
export KEYPATH_PROJECT_DIR="$SCRIPT_DIR/.."
keypath_use_stable_xcode
keypath_acquire_deploy_lock "build-and-sign ($SCRIPT_DIR/..)" "${KEYPATH_RELEASE_DEPLOY_LOCK_TIMEOUT_SECONDS:-600}"
trap keypath_release_deploy_lock EXIT

# Function to create Sparkle update archive with EdDSA signature.
#
# Defined near the top so it can be invoked from the main build flow below.
create_sparkle_archive() {
    if [ "${SKIP_SPARKLE:-0}" = "1" ]; then
        echo "⏭️  Skipping Sparkle update archive (SKIP_SPARKLE=1)"
        return 0
    fi
    echo ""
    echo "✨ Creating Sparkle update archive..."

    # Extract version from Info.plist
    local VERSION
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS/Info.plist" 2>/dev/null || echo "1.0.0")
    local BUILD
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CONTENTS/Info.plist" 2>/dev/null || echo "1")
    local ARCHIVE_NAME="KeyPath-${VERSION}.zip"
    local SPARKLE_DIR="${DIST_DIR}/sparkle"

    mkdir -p "$SPARKLE_DIR"

    # Create versioned ZIP for Sparkle (separate from the notarization zip)
    echo "📦 Creating versioned archive: $ARCHIVE_NAME"
    cd "$DIST_DIR"
    ditto -c -k --keepParent "${APP_NAME}.app" "sparkle/${ARCHIVE_NAME}"
    cd ..

    local GENERATE_APPCAST
    GENERATE_APPCAST="$(keypath_resolve_sparkle_tool generate_appcast)" || {
        echo "❌ ERROR: Sparkle generate_appcast is unavailable." >&2
        return 1
    }
    local FEED_WORK_DIR="${SPARKLE_DIR}/feed"
    mkdir -p "$FEED_WORK_DIR"
    ditto "$SCRIPT_DIR/../appcast.xml" "$FEED_WORK_DIR/appcast.xml"
    ditto "${SPARKLE_DIR}/${ARCHIVE_NAME}" "$FEED_WORK_DIR/${ARCHIVE_NAME}"

    local APPCAST_ARGS=(
        --download-url-prefix "https://github.com/malpern/KeyPath/releases/download/v${VERSION}/"
        --full-release-notes-url "https://github.com/malpern/KeyPath/releases/tag/v${VERSION}"
        --link "https://keypath-app.com"
        --versions "$BUILD"
        --maximum-versions 0
        --maximum-deltas 0
    )
    if [[ "$VERSION" == *-* ]]; then
        APPCAST_ARGS+=(--channel beta)
    else
        APPCAST_ARGS+=(--phased-rollout-interval 86400)
    fi

    echo "📝 Generating and signing complete appcast with Sparkle..."
    keypath_run_generate_appcast "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$FEED_WORK_DIR"
    keypath_verify_sparkle_feed "$FEED_WORK_DIR/appcast.xml"
    ditto "$FEED_WORK_DIR/appcast.xml" "$SPARKLE_DIR/appcast.xml"
    echo "✅ Sparkle archive and signed appcast verified"

    # Create styled DMG with background image and icon positioning
    local DMG_NAME="KeyPath-${VERSION}.dmg"
    local DMG_BG="${SCRIPT_DIR}/../dev-tools/dmg/dmg-background@2x.png"
    echo "💿 Creating DMG installer..."
    rm -f "${SPARKLE_DIR}/${DMG_NAME}"
    if command -v create-dmg >/dev/null 2>&1 && [ -f "$DMG_BG" ]; then
        create-dmg \
            --volname "KeyPath" \
            --background "$DMG_BG" \
            --window-pos 200 120 \
            --window-size 660 400 \
            --icon-size 128 \
            --icon "${APP_NAME}.app" 175 200 \
            --hide-extension "${APP_NAME}.app" \
            --app-drop-link 485 200 \
            --no-internet-enable \
            "${SPARKLE_DIR}/${DMG_NAME}" \
            "${DIST_DIR}/${APP_NAME}.app" >/dev/null 2>&1
    else
        # Fallback: plain DMG without styling
        local DMG_STAGING="${DIST_DIR}/dmg-staging"
        rm -rf "$DMG_STAGING"
        mkdir -p "$DMG_STAGING"
        cp -R "${DIST_DIR}/${APP_NAME}.app" "$DMG_STAGING/"
        ln -s /Applications "$DMG_STAGING/Applications"
        hdiutil create -volname "KeyPath" -srcfolder "$DMG_STAGING" \
            -ov -format UDZO "${SPARKLE_DIR}/${DMG_NAME}" >/dev/null 2>&1
        rm -rf "$DMG_STAGING"
    fi
    echo "   ✅ DMG created: ${SPARKLE_DIR}/${DMG_NAME}"

    echo ""
    echo "✅ Sparkle archive created:"
    echo "   📦 Archive: ${SPARKLE_DIR}/${ARCHIVE_NAME}"
    echo "   📝 Signed appcast: ${SPARKLE_DIR}/appcast.xml"
    echo "   💿 DMG: ${SPARKLE_DIR}/${DMG_NAME}"
}

keypath_ensure_kanata_submodule "$SCRIPT_DIR/.."
"$SCRIPT_DIR/verify-release-signing-contract.sh" --source
if [ "${SKIP_SPARKLE:-0}" != "1" ]; then
    keypath_load_sparkle_private_key || true
    keypath_verify_sparkle_signing_identity "$SCRIPT_DIR/../Sources/KeyPathApp/Info.plist"
    echo "✅ Sparkle signing identity '$KEYPATH_SPARKLE_ACCOUNT' matches SUPublicEDKey"
fi

echo "🦀 Building Rust artifacts in parallel (kanata, simulator, host bridge)..."
./Scripts/build-kanata.sh &
KANATA_PID=$!
./Scripts/build-kanata-simulator.sh &
SIM_PID=$!
./Scripts/build-kanata-host-bridge.sh &
BRIDGE_PID=$!

RUST_FAILED=0
wait $KANATA_PID || RUST_FAILED=1
wait $SIM_PID || RUST_FAILED=1
wait $BRIDGE_PID || RUST_FAILED=1
if [ $RUST_FAILED -ne 0 ]; then
    echo "❌ One or more Rust builds failed" >&2
    exit 1
fi
echo "✅ All Rust builds complete"

echo "🔐 Building privileged helper..."
# Build and sign the helper tool
./Scripts/build-helper.sh

# Screenshot regeneration is only needed for full public release builds or when
# help/snapshot assets intentionally changed. Release-candidate builds should set
# SKIP_SNAPSHOTS=1 to avoid spending time regenerating unrelated images.
if [ "${SKIP_SNAPSHOTS:-}" = "1" ]; then
    echo "⏭️  Skipping screenshot regeneration (SKIP_SNAPSHOTS=1)"
elif [ "${SKIP_SNAPSHOTS:-}" = "0" ] || [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo "📸 Regenerating help screenshots..."
    SKIP_PEEKABOO="${SKIP_PEEKABOO:-1}" ./Scripts/regenerate-screenshots.sh
else
    echo "⏭️  Skipping screenshot regeneration (dev build)"
fi

echo "🏗️  Building KeyPath and plugins..."
# Build all products in a single SwiftPM invocation to share module compilation.
BUILD_SYSTEM_FLAGS=()
if [[ -n "${KEYPATH_BUILD_SYSTEM:-}" && "${KEYPATH_BUILD_SYSTEM:-}" != "native" ]]; then
    BUILD_SYSTEM_FLAGS=(--build-system "$KEYPATH_BUILD_SYSTEM")
fi
swift build ${BUILD_SYSTEM_FLAGS[@]+"${BUILD_SYSTEM_FLAGS[@]}"} --configuration release -Xswiftc -no-whole-module-optimization

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

	# Copy command-line tool. Keep the filename distinct from KeyPath on
	# case-insensitive filesystems; users can opt into a shell shim from the app.
	ditto "$BUILD_DIR/keypath-cli" "$MACOS/keypath-cli"

	# Ensure app-bundle rpath can locate embedded frameworks
	# SwiftPM-built executables usually have LC_RPATH=@loader_path, which points to Contents/MacOS.
	# For an app bundle, frameworks live at Contents/Frameworks, so add that search path.
	install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/KeyPath" 2>/dev/null || true
	install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/keypath-cli" 2>/dev/null || true

	# Create "Kanata Engine.app" bundle wrapping the kanata binary.
	# This gives kanata a CFBundleIdentifier so macOS TCC tracks it by bundle ID
	# (client_type=0) instead of raw path (client_type=1), which ensures it appears
	# in System Settings on macOS Tahoe 26.1+ and survives path changes.
	KANATA_ENGINE_APP="$CONTENTS/Library/KeyPath/Kanata Engine.app"
	KANATA_ENGINE_CONTENTS="$KANATA_ENGINE_APP/Contents"
	KANATA_ENGINE_MACOS="$KANATA_ENGINE_CONTENTS/MacOS"
	mkdir -p "$KANATA_ENGINE_MACOS"

	# Move kanata binary into the .app bundle
	ditto "build/kanata-universal" "$KANATA_ENGINE_MACOS/kanata"

	# Copy committed Info.plist for "Kanata Engine.app"
	cp "$SCRIPT_DIR/../Sources/KeyPathApp/Resources/KanataEngine-Info.plist" "$KANATA_ENGINE_CONTENTS/Info.plist"

	# Copy icon into "Kanata Engine.app"/Contents/Resources/
	KANATA_ENGINE_RESOURCES="$KANATA_ENGINE_CONTENTS/Resources"
	mkdir -p "$KANATA_ENGINE_RESOURCES"
	KANATA_ICON_SRC="$SCRIPT_DIR/../Sources/KeyPathApp/Resources/KanataEngineIcon.icns"
	if [ -f "$KANATA_ICON_SRC" ]; then
	    ditto "$KANATA_ICON_SRC" "$KANATA_ENGINE_RESOURCES/KanataEngineIcon.icns"
	fi

	# Inject the main app's version into "Kanata Engine.app" so the bundle version
	# stays in sync across releases (the source plist uses placeholder values).
	_MAIN_VER=$(defaults read "$SCRIPT_DIR/../Sources/KeyPathApp/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
	_MAIN_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SCRIPT_DIR/../Sources/KeyPathApp/Info.plist" 2>/dev/null || echo "1")
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $_MAIN_VER" "$KANATA_ENGINE_CONTENTS/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $_MAIN_BUILD" "$KANATA_ENGINE_CONTENTS/Info.plist"

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
	if [ ! -f "$FRAMEWORKS/Sparkle.framework/Versions/B/Sparkle" ]; then
	    echo "❌ ERROR: Embedded Sparkle binary is missing from $FRAMEWORKS/Sparkle.framework" >&2
	    exit 1
	fi
	for executable in "$MACOS/KeyPath" "$MACOS/keypath-cli"; do
	    if ! otool -l "$executable" | grep -q "@executable_path/../Frameworks"; then
	        echo "❌ ERROR: $(basename "$executable") is missing @executable_path/../Frameworks rpath" >&2
	        echo "   Without this, dyld cannot load the embedded Sparkle.framework at launch." >&2
	        exit 1
	    fi
	done

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

# Copy daemon plist into bundle-local LaunchDaemons with final name
ditto "Sources/KeyPathHelper/com.keypath.helper.plist" "$LAUNCH_DAEMONS/com.keypath.helper.plist"

# Copy Kanata daemon plist for SMAppService
ditto "Sources/KeyPathApp/com.keypath.kanata.plist" "$LAUNCH_DAEMONS/com.keypath.kanata.plist"

	verify_embedded_artifacts() {
	    local missing=0
	    for path in \
	        "$HELPER_TOOLS/KeyPathHelper" \
	        "$MACOS/keypath-cli" \
	        "$LAUNCH_DAEMONS/com.keypath.helper.plist" \
	        "$LAUNCH_DAEMONS/com.keypath.kanata.plist" \
	        "$FRAMEWORKS/Sparkle.framework" \
	        "$INSIGHTS_BUNDLE/Contents/MacOS/libKeyPathInsights" \
	        "$INSIGHTS_BUNDLE/Contents/Info.plist" \
	        "$KANATA_LAUNCHER_DST" \
	        "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" \
	        "$CONTENTS/Library/KeyPath/kanata-simulator" \
	        "$CONTENTS/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" \
	        "$CONTENTS/Library/KeyPath/Kanata Engine.app/Contents/Info.plist"; do
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
    echo "⚠️ WARNING: Sources/KeyPathApp/Resources directory not found"
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
CFVER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS/Info.plist" 2>/dev/null || echo "1.0.0")
CFBUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CONTENTS/Info.plist" 2>/dev/null || echo "0")
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

    # Sign "Kanata Engine.app" bundle inside-out: sign the inner binary first, then the bundle.
    kp_sign "$CONTENTS/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" --force --options=runtime --sign "$SIGNING_IDENTITY"
    kp_sign "$CONTENTS/Library/KeyPath/Kanata Engine.app" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign the bundled runtime host pieces explicitly before the outer app sign.
    kp_sign "$CONTENTS/Library/KeyPath/kanata-launcher" --force --options=runtime --sign "$SIGNING_IDENTITY"
    kp_sign "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign bundled kanata simulator binary
    kp_sign "$CONTENTS/Library/KeyPath/kanata-simulator" --force --options=runtime --sign "$SIGNING_IDENTITY"

    # Sign command-line tool embedded in the app bundle with a stable identifier
    # trusted by the privileged helper for CLI system diagnostics and repair.
    kp_sign "$MACOS/keypath-cli" \
        --force --options=runtime \
        --identifier "com.keypath.KeyPath.CLI" \
        --sign "$SIGNING_IDENTITY"

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
    "$SCRIPT_DIR/verify-identity-contract.sh" --app "$APP_BUNDLE"
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
    # Prefer the file-based App Store Connect API key when present: keychain
    # profiles become unreadable if the session locks mid-build.
    kp_notary_default_auth_from_environment
    kp_notarize_zip "${DIST_DIR}/${APP_NAME}.zip" "$NOTARY_PROFILE"

    echo "🔖 Stapling notarization..."
    kp_staple "$APP_BUNDLE"

    echo "🎉 Build complete!"
    echo "📍 Signed app: $APP_BUNDLE"
    echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

    echo "🔍 Final verification..."
    kp_spctl_assess "$APP_BUNDLE"

    echo "✨ Ready for distribution!"

fi

# Sparkle generation is controlled independently from notarization. Public
# releases still require notarization, while SKIP_NOTARIZE=1 + SKIP_DEPLOY=1
# provides a safe way to exercise signing and appcast generation locally.
create_sparkle_archive

if [ "${SKIP_DEPLOY:-0}" = "1" ]; then
    echo "⏭️  Skipping deployment (SKIP_DEPLOY=1)"
    echo "📍 Candidate retained at: $APP_BUNDLE"
    exit 0
fi

# A build that was submitted for notarization must never reach /Applications
# without its stapled ticket: Gatekeeper rejects the installed copy, and any
# later local re-sign changes the cdhash so the eventual ticket can no longer
# be stapled in place (2026-07-30 RC incident).
if [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo "🔎 Verifying stapled ticket before deploy..."
    if ! kp_staple_validate "$APP_BUNDLE"; then
        echo "❌ $APP_BUNDLE has no valid stapled notarization ticket; refusing to deploy." >&2
        echo "   Resume without rebuilding: Scripts/release-candidate.sh --resume-notarization" >&2
        exit 1
    fi
fi

kp_deploy_bundle_to_applications "$APP_BUNDLE" "$APP_NAME"

# ─────────────────────────────────────────────────────────────────────
# Publish help content to website
# ─────────────────────────────────────────────────────────────────────

GHPAGES_DIR="$SCRIPT_DIR/../.worktrees/gh-pages"
if [ -d "$GHPAGES_DIR" ] && [ "${SKIP_WEBSITE:-0}" != "1" ] && [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo ""
    echo "🌐 Publishing help content to website..."
    "$SCRIPT_DIR/publish-guides.sh"

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
