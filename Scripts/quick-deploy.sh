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
ENTITLEMENTS="$PROJECT_DIR/KeyPath.entitlements"

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

# Build debug (fast - incremental)
echo "🔨 Building..."
BUILD_LOG=$(mktemp -t keypath-build.XXXXXX)
if ! BIN_DIR=$(swift build --product KeyPath --show-bin-path "${MODULE_CACHE_FLAGS[@]}" 2> "$BUILD_LOG" | tail -1); then
    BUILD_END_MS=$(get_time_ms)
    DURATION=$((BUILD_END_MS - BUILD_START_MS))
    echo "❌ Build failed"
    tail -3 "$BUILD_LOG" || true
    rm -f "$BUILD_LOG"
    log_build_event "BUILD_FAILED" "$DURATION"
    exit 1
fi
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

# Add the missing rpath for Sparkle framework (debug builds don't have this)
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Re-sign with entitlements (prefer Developer ID if available)
echo "✍️  Signing..."
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null
else
    echo "⚠️  Developer ID identity not found; using ad-hoc signing (helper may reject this build)."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null
fi

# Restart the app
echo "🔄 Restarting..."
if pgrep -x "$APP_NAME" > /dev/null; then
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.3
fi

open "$APP_BUNDLE"

BUILD_END_MS=$(get_time_ms)
DURATION=$((BUILD_END_MS - BUILD_START_MS))

echo "✅ Done! (${DURATION}ms)"
log_build_event "SUCCESS" "$DURATION"
