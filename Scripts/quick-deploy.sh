#!/bin/bash
# Quick deploy for development: build, copy to /Applications, restart
# No signing or notarization - just fast iteration (~3-4 seconds)
#
# Features:
# - Lock-based concurrency control (skips if another build is running)
# - Build time instrumentation (logs to .build/build-stats.log)
# - Cancellation tracking
#
# Prerequisites: Run ./build.sh once to create the initial app bundle structure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
APP_NAME="KeyPath"
APP_BUNDLE="/Applications/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ENTITLEMENTS="$PROJECT_DIR/KeyPath.entitlements"
WAS_RUNNING=0

# Local module cache to avoid invalidations and sandboxed cache paths.
MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache.noindex"
export CLANG_MODULECACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE"
MODULE_CACHE_FLAGS=(-Xcc "-fmodules-cache-path=$MODULE_CACHE")

# Build instrumentation
BUILD_STATS_FILE="$PROJECT_DIR/.build/build-stats.log"
LOCK_FILE="$PROJECT_DIR/.build/quick-deploy.lock"
BUILD_ID="$(date +%s%N | cut -c1-13)"  # Millisecond timestamp as build ID

cd "$PROJECT_DIR"

# Ensure .build directory exists for stats
mkdir -p "$PROJECT_DIR/.build" "$MODULE_CACHE"

# --- Instrumentation Functions ---

log_build_event() {
    local event="$1"
    local duration="${2:-0}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $event | build_id=$BUILD_ID | duration_ms=$duration" >> "$BUILD_STATS_FILE"
}

get_time_ms() {
    # Cross-platform milliseconds (macOS doesn't have %N in date)
    python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s000
}

# --- Lock Management ---

acquire_lock() {
    # Try to create lock file atomically
    # If lock exists and process is still running, skip this build
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            # Another build is actually running
            echo "⏭️  Build already in progress (PID $lock_pid), skipping..."
            log_build_event "SKIPPED_CONCURRENT"
            return 1
        else
            # Stale lock file - remove it
            rm -f "$LOCK_FILE"
        fi
    fi

    # Create lock with our PID
    echo $$ > "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

cleanup() {
    local exit_code=$?
    release_lock

    if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 130 ]]; then
        # Non-zero exit that isn't SIGINT
        log_build_event "FAILED" "0"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# --- Main Build Logic ---

# Try to acquire lock
if ! acquire_lock; then
    exit 0  # Exit cleanly - not an error, just skipped
fi

BUILD_START_MS=$(get_time_ms)
log_build_event "STARTED"

# Check prerequisites
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ App bundle not found at $APP_BUNDLE"
    echo "💡 Run './build.sh' once to create the initial app structure"
    log_build_event "FAILED_NO_BUNDLE"
    exit 1
fi

# Check if SwiftPM is already building (additional safety)
SWIFTPM_LOCK="$PROJECT_DIR/.build/workspace-state.json"
if [[ -f "$SWIFTPM_LOCK" ]] && lsof "$SWIFTPM_LOCK" 2>/dev/null | grep -q swift; then
    echo "⏭️  SwiftPM build in progress, skipping..."
    log_build_event "SKIPPED_SWIFTPM_BUSY"
    exit 0
fi

# Stop the currently running app before mutating the bundle on disk.
#
# Replacing binaries and re-signing a live .app can invalidate pages that the old
# process still has mapped, which shows up as a crash report with:
#   SIGKILL (Code Signature Invalid)
#   namespace CODESIGNING / Invalid Page
#
# We intentionally stop the app up front, then rebuild/copy/sign, then relaunch.
if pgrep -x "$APP_NAME" > /dev/null; then
    WAS_RUNNING=1
    echo "🛑 Stopping running $APP_NAME before deploy..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    for _ in {1..120}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.05
    done
fi

# Build debug (fast - incremental)
echo "🔨 Building..."
BUILD_LOG=$(mktemp -t keypath-build.XXXXXX)
# NOTE: `swift build --show-bin-path` does not reliably trigger a rebuild.
# Always build first, then query the bin dir.
if ! swift build --product KeyPath --product KeyPathKanataLauncher --product KeyPathOutputBridge --product KeyPathInsights "${MODULE_CACHE_FLAGS[@]}" 2> "$BUILD_LOG"; then
    BUILD_END_MS=$(get_time_ms)
    DURATION=$((BUILD_END_MS - BUILD_START_MS))
    echo "❌ Build failed"
    tail -3 "$BUILD_LOG" || true
    rm -f "$BUILD_LOG"
    log_build_event "BUILD_FAILED" "$DURATION"
    exit 1
fi

BIN_DIR=$(swift build --show-bin-path "${MODULE_CACHE_FLAGS[@]}" 2>> "$BUILD_LOG" | tail -1)
tail -3 "$BUILD_LOG" || true
rm -f "$BUILD_LOG"

# Get the built binary
DEBUG_BIN="$BIN_DIR/KeyPath"

if [[ ! -f "$DEBUG_BIN" ]]; then
    echo "❌ Build failed - binary not found"
    log_build_event "FAILED_NO_BINARY"
    exit 1
fi

# Copy binary to app bundle
echo "📦 Deploying..."
cp "$DEBUG_BIN" "$MACOS_DIR/$APP_NAME"

# Do not hot-swap the embedded privileged helper by default.
#
# The helper is registered via SMAppService and launchd keeps launch constraints
# tied to the previously blessed bundle contents. Replacing the helper binary
# inside /Applications during quick iteration can leave the registered helper in
# a spawn-failed state until it is explicitly re-registered. Opt in only when
# you intend to follow with a helper reinstall/repair flow.
if [[ "${KEYPATH_DEPLOY_HELPER:-0}" == "1" ]]; then
    ./Scripts/build-helper.sh >/dev/null

    HELPER_BIN="$PROJECT_DIR/.build/arm64-apple-macosx/release/KeyPathHelper"
    HELPER_DST="$APP_BUNDLE/Contents/Library/HelperTools/KeyPathHelper"
    if [[ -f "$HELPER_BIN" ]]; then
        mkdir -p "$(dirname "$HELPER_DST")"
        cp "$HELPER_BIN" "$HELPER_DST"
        chmod 755 "$HELPER_DST"
        echo "⚠️  Deployed embedded helper. Re-register the privileged helper before testing XPC."
    fi
fi

# Ensure "Kanata Engine.app" bundle structure exists around the kanata binary.
# The full build creates this; quick-deploy just ensures it's present.
KANATA_ENGINE_APP="$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app"
KANATA_ENGINE_CONTENTS="$KANATA_ENGINE_APP/Contents"
KANATA_ENGINE_MACOS="$KANATA_ENGINE_CONTENTS/MacOS"
mkdir -p "$KANATA_ENGINE_MACOS"

# If the kanata binary exists at the old flat location (not a symlink), migrate it
# into the .app bundle and leave a backward-compat symlink behind.
OLD_KANATA="$APP_BUNDLE/Contents/Library/KeyPath/kanata"
if [[ -f "$OLD_KANATA" && ! -L "$OLD_KANATA" ]]; then
    mv "$OLD_KANATA" "$KANATA_ENGINE_MACOS/kanata"
    ln -sf "Kanata Engine.app/Contents/MacOS/kanata" "$OLD_KANATA"
fi

# Ensure the kanata binary is present inside "Kanata Engine.app".
# On a fresh deploy the binary may not exist yet (no old flat binary to migrate).
# Copy from the pre-built artifact if available.
KANATA_UNIVERSAL="$PROJECT_DIR/build/kanata-universal"
if [[ ! -f "$KANATA_ENGINE_MACOS/kanata" && -f "$KANATA_UNIVERSAL" ]]; then
    cp "$KANATA_UNIVERSAL" "$KANATA_ENGINE_MACOS/kanata"
    chmod 755 "$KANATA_ENGINE_MACOS/kanata"
    # Create backward-compat symlink if missing
    if [[ ! -e "$OLD_KANATA" ]]; then
        ln -sf "Kanata Engine.app/Contents/MacOS/kanata" "$OLD_KANATA"
    fi
fi

if [[ ! -f "$KANATA_ENGINE_MACOS/kanata" ]]; then
    echo "⚠️  Kanata Engine.app has no kanata binary. Run ./Scripts/build-kanata.sh first."
fi

# Copy committed Info.plist
cp "$PROJECT_DIR/Sources/KeyPathApp/Resources/KanataEngine-Info.plist" "$KANATA_ENGINE_CONTENTS/Info.plist"

# Copy icon into "Kanata Engine.app"/Contents/Resources/
KANATA_ENGINE_RESOURCES="$KANATA_ENGINE_CONTENTS/Resources"
mkdir -p "$KANATA_ENGINE_RESOURCES"
KANATA_ICON_SRC="$PROJECT_DIR/Sources/KeyPathApp/Resources/KanataEngineIcon.icns"
if [[ -f "$KANATA_ICON_SRC" ]]; then
    cp "$KANATA_ICON_SRC" "$KANATA_ENGINE_RESOURCES/KanataEngineIcon.icns"
fi

# Inject the main app's version into "Kanata Engine.app" so the bundle version
# stays in sync across releases (the source plist uses placeholder values).
_MAIN_VER=$(defaults read "$PROJECT_DIR/Sources/KeyPathApp/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
_MAIN_BUILD=$(defaults read "$PROJECT_DIR/Sources/KeyPathApp/Info" CFBundleVersion 2>/dev/null || echo "1")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $_MAIN_VER" "$KANATA_ENGINE_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $_MAIN_BUILD" "$KANATA_ENGINE_CONTENTS/Info.plist"

# Sync the current bundled runtime host executable.
KANATA_LAUNCHER_BIN="$BIN_DIR/KeyPathKanataLauncher"
KANATA_LAUNCHER_DST="$APP_BUNDLE/Contents/Library/KeyPath/kanata-launcher"
if [[ -f "$KANATA_LAUNCHER_BIN" ]]; then
    mkdir -p "$(dirname "$KANATA_LAUNCHER_DST")"
    cp "$KANATA_LAUNCHER_BIN" "$KANATA_LAUNCHER_DST"
    chmod 755 "$KANATA_LAUNCHER_DST"
fi

OUTPUT_BRIDGE_BIN="$BIN_DIR/KeyPathOutputBridge"
OUTPUT_BRIDGE_DST="$APP_BUNDLE/Contents/Library/HelperTools/KeyPathOutputBridge"
if [[ -f "$OUTPUT_BRIDGE_BIN" ]]; then
    mkdir -p "$(dirname "$OUTPUT_BRIDGE_DST")"
    cp "$OUTPUT_BRIDGE_BIN" "$OUTPUT_BRIDGE_DST"
    chmod 755 "$OUTPUT_BRIDGE_DST"
fi

OUTPUT_BRIDGE_PLIST_SRC="$PROJECT_DIR/Sources/KeyPathOutputBridge/com.keypath.output-bridge.plist"
OUTPUT_BRIDGE_PLIST_DST="$APP_BUNDLE/Contents/Library/LaunchDaemons/com.keypath.output-bridge.plist"
if [[ -f "$OUTPUT_BRIDGE_PLIST_SRC" ]]; then
    mkdir -p "$(dirname "$OUTPUT_BRIDGE_PLIST_DST")"
    cp "$OUTPUT_BRIDGE_PLIST_SRC" "$OUTPUT_BRIDGE_PLIST_DST"
fi

# Rebuild the Rust host bridge so the installed app does not silently reuse a stale
# dylib without the passthru runtime feature set required by the split-runtime host.
./Scripts/build-kanata-host-bridge.sh >/dev/null

KANATA_HOST_BRIDGE_SRC="$PROJECT_DIR/build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib"
KANATA_HOST_BRIDGE_DST="$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"
if [[ -f "$KANATA_HOST_BRIDGE_SRC" ]]; then
    mkdir -p "$(dirname "$KANATA_HOST_BRIDGE_DST")"
    cp "$KANATA_HOST_BRIDGE_SRC" "$KANATA_HOST_BRIDGE_DST"
fi

# Sync app resources for fast iteration (quick-deploy doesn't rebuild the bundle).
# This ensures new images/scripts added under Sources/KeyPathApp/Resources show up
# immediately without requiring a full ./build.sh.
mkdir -p "$RESOURCES_DIR"
if command -v rsync >/dev/null 2>&1; then
    rsync -a "$PROJECT_DIR/Sources/KeyPathApp/Resources/" "$RESOURCES_DIR/"
else
    cp -R "$PROJECT_DIR/Sources/KeyPathApp/Resources/." "$RESOURCES_DIR/"
fi

# Sync SwiftPM resource bundles (e.g. KeyPath_KeyPathAppKit.bundle) so that
# newly added images, markdown docs, etc. appear without a full ./build.sh.
for bundle in "$BIN_DIR"/KeyPath_*.bundle; do
    [[ -d "$bundle" ]] || continue
    rsync -a "$bundle" "$RESOURCES_DIR/"
done

# Add the missing rpath for Sparkle framework (debug builds don't have this)
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Assemble and sync Insights.bundle to PlugIns
INSIGHTS_DYLIB="$BIN_DIR/libKeyPathInsights.dylib"
if [[ -f "$INSIGHTS_DYLIB" ]]; then
    INSIGHTS_BUNDLE="$APP_BUNDLE/Contents/PlugIns/Insights.bundle/Contents/MacOS"
    mkdir -p "$INSIGHTS_BUNDLE"
    cp "$INSIGHTS_DYLIB" "$INSIGHTS_BUNDLE/libKeyPathInsights"
    cp "$PROJECT_DIR/Sources/KeyPathInsights/Info.plist" "$APP_BUNDLE/Contents/PlugIns/Insights.bundle/Contents/Info.plist"
fi

# Re-sign with entitlements (prefer Developer ID if available).
# NOTE: "Kanata Engine.app" and inner binaries are signed here WITHOUT entitlements
# (just --options=runtime). This produces a dev-only ad-hoc-equivalent signature
# sufficient for local testing, but NOT equivalent to the distribution signature
# from build-and-sign.sh which applies proper entitlements and a notarizable
# Developer ID identity to every artifact.
echo "✍️  Signing..."
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    if [[ -f "$APP_BUNDLE/Contents/Library/HelperTools/KeyPathHelper" ]]; then
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/HelperTools/KeyPathHelper" 2>/dev/null || true
    fi
    if [[ -d "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app" ]]; then
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" || echo "⚠️  Failed to sign Kanata Engine kanata binary"
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app" || echo "⚠️  Failed to sign Kanata Engine.app bundle"
    fi
    if [[ -f "$APP_BUNDLE/Contents/Library/KeyPath/kanata-launcher" ]]; then
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/kanata-launcher" 2>/dev/null || true
    fi
    if [[ -f "$APP_BUNDLE/Contents/Library/HelperTools/KeyPathOutputBridge" ]]; then
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/HelperTools/KeyPathOutputBridge" 2>/dev/null || true
    fi
    if [[ -f "$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" ]]; then
        codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" 2>/dev/null || true
    fi
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null
else
    echo "⚠️  Developer ID identity not found; using ad-hoc signing (helper may reject this build)."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null
fi

# Restart the app only if it was running when deploy began.
if [[ "$WAS_RUNNING" == "1" ]]; then
    echo "🔄 Restarting..."
    open "$APP_BUNDLE"
else
    echo "ℹ️  Deploy complete; app was not running, so it was not relaunched."
fi

BUILD_END_MS=$(get_time_ms)
DURATION=$((BUILD_END_MS - BUILD_START_MS))

echo "✅ Done! (${DURATION}ms)"
log_build_event "SUCCESS" "$DURATION"
