#!/bin/bash
# Quick deploy for development: build, copy to /Applications, sign locally, restart.
# This intentionally does not notarize. By default it builds only the KeyPath app
# product for UI iteration; set KEYPATH_QUICK_DEPLOY_BUILD_SCOPE=full to refresh
# companion binaries such as keypath-cli.
#
# Features:
# - Lock-based concurrency control (skips if another build is running)
# - Build time instrumentation (logs to .build/build-stats.log)
# - Cancellation tracking
#
# Prerequisites: Run ./build.sh once to create the initial app bundle structure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
source "$SCRIPT_DIR/lib/xcode.sh"
source "$SCRIPT_DIR/lib/deploy-lock.sh"
source "$SCRIPT_DIR/lib/build-cache.sh"
keypath_use_stable_xcode
APP_NAME="KeyPath"
APP_BUNDLE="/Applications/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ENTITLEMENTS="$PROJECT_DIR/KeyPath.entitlements"
WAS_RUNNING=0
BUILD_SCOPE="${KEYPATH_QUICK_DEPLOY_BUILD_SCOPE:-app}"
if [[ "$BUILD_SCOPE" != "app" && "$BUILD_SCOPE" != "full" ]]; then
    echo "❌ KEYPATH_QUICK_DEPLOY_BUILD_SCOPE must be 'app' or 'full' (got '$BUILD_SCOPE')" >&2
    exit 1
fi
HOST_BRIDGE_MODE="${KEYPATH_QUICK_DEPLOY_HOST_BRIDGE:-}"
if [[ -z "$HOST_BRIDGE_MODE" ]]; then
    if [[ "$BUILD_SCOPE" == "full" ]]; then
        HOST_BRIDGE_MODE=1
    else
        HOST_BRIDGE_MODE=0
    fi
fi

# KeepAlive LaunchAgent that runs the headless KeyPath instance. We unload it for
# the build+sign window so launchd can't respawn KeyPath onto a bundle whose
# signature is mid-rewrite — that race produces a crash report with
# SIGKILL (Code Signature Invalid) / Taskgated Invalid Signature.
AGENT_LABEL="com.keypath.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"
AGENT_DOMAIN="gui/$(id -u)"
AGENT_WAS_LOADED=0

# Local module cache to avoid invalidations and sandboxed cache paths.
MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache.noindex"
export CLANG_MODULECACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE"
MODULE_CACHE_FLAGS=(-Xcc "-fmodules-cache-path=$MODULE_CACHE")

# Build instrumentation
BUILD_STATS_FILE="$PROJECT_DIR/.build/build-stats.log"
BUILD_LOG_DIR="$PROJECT_DIR/.build/logs/quick-deploy"
BUILD_LOG_RETENTION_DAYS="${KEYPATH_QUICK_DEPLOY_LOG_RETENTION_DAYS:-7}"
LOCK_FILE="$PROJECT_DIR/.build/quick-deploy.lock"
BUILD_ID="$(date +%s%N | cut -c1-13)"  # Millisecond timestamp as build ID

cd "$PROJECT_DIR"

# Ensure .build directory exists for stats
mkdir -p "$PROJECT_DIR/.build" "$MODULE_CACHE" "$BUILD_LOG_DIR"
keypath_prepare_build_cache "$PROJECT_DIR" "$PROJECT_DIR/.build"
mkdir -p "$MODULE_CACHE" "$BUILD_LOG_DIR"

# --- Instrumentation Functions ---

log_build_event() {
    local event="$1"
    local duration="${2:-0}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $event | build_id=$BUILD_ID | duration_ms=$duration" >> "$BUILD_STATS_FILE"
}

get_time_ms() {
    perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time()*1000' 2>/dev/null || echo "$(($(date +%s) * 1000))"
}

prune_old_build_logs() {
    local retention_days="$BUILD_LOG_RETENTION_DAYS"
    if [[ ! "$retention_days" =~ ^[0-9]+$ ]]; then
        retention_days=7
    fi
    find "$BUILD_LOG_DIR" -type f -name "build-*.log" -mtime +"$retention_days" -delete 2>/dev/null || true
}

write_build_log_header() {
    local log_file="$1"
    {
        echo "quick-deploy build diagnostics"
        echo "timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "build_id: $BUILD_ID"
        echo "project_dir: $PROJECT_DIR"
        echo "branch: $(git branch --show-current 2>/dev/null || echo unknown)"
        echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        echo "DEVELOPER_DIR: ${DEVELOPER_DIR:-}"
        echo "build_scope: $BUILD_SCOPE"
        echo "host_bridge_mode: $HOST_BRIDGE_MODE"
        echo "CLANG_MODULECACHE_PATH: ${CLANG_MODULECACHE_PATH:-}"
        echo "SWIFT_MODULECACHE_PATH: ${SWIFT_MODULECACHE_PATH:-}"
        echo "module_cache_flags: ${MODULE_CACHE_FLAGS[*]}"
        echo "--- swift build output ---"
    } > "$log_file"
}

print_build_failure_diagnostics() {
    local log_file="$1"
    echo "❌ Build failed"
    echo "🧾 Full build log preserved at: $log_file"
    echo "   build_id=$BUILD_ID"
    echo "   CLANG_MODULECACHE_PATH=${CLANG_MODULECACHE_PATH:-}"
    echo "   SWIFT_MODULECACHE_PATH=${SWIFT_MODULECACHE_PATH:-}"
    echo "   module_cache_flags=${MODULE_CACHE_FLAGS[*]}"

    local first_match
    first_match=$(
        awk '
            /^--- swift build output ---$/ { in_output = 1; next }
            in_output && /error:|fatal error:|Stack dump|Please submit a bug report|swift-frontend/ { print NR; exit }
        ' "$log_file" || true
    )
    if [[ -n "$first_match" ]]; then
        local start=$((first_match - 12))
        local end=$((first_match + 40))
        if (( start < 1 )); then
            start=1
        fi
        echo "---- first relevant diagnostic (${start}-${end}) ----"
        sed -n "${start},${end}p" "$log_file" || true
    else
        echo "---- no compiler diagnostic marker found ----"
    fi

    echo "---- final 120 build log lines ----"
    tail -120 "$log_file" || true
}

prune_old_build_logs

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

# Re-load the KeepAlive agent we unloaded for the signing window. Idempotent:
# only bootstraps when we actually unloaded it and it isn't already loaded.
# RunAtLoad=true makes launchd relaunch the headless KeyPath instance.
reload_agent() {
    if [[ "$AGENT_WAS_LOADED" == "1" ]] && [[ -f "$AGENT_PLIST" ]]; then
        if ! launchctl print "${AGENT_DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
            echo "▶️  Reloading ${AGENT_LABEL}..."
            launchctl bootstrap "${AGENT_DOMAIN}" "$AGENT_PLIST" 2>/dev/null || true
        fi
    fi
}

cleanup() {
    local exit_code=$?
    # Always restore the agent, even on failure, so KeyPath is never left disabled.
    reload_agent
    keypath_release_deploy_lock
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

if ! keypath_acquire_deploy_lock "quick-deploy ($PROJECT_DIR)" "${KEYPATH_QUICK_DEPLOY_LOCK_TIMEOUT_SECONDS:-0}"; then
    log_build_event "SKIPPED_DEPLOY_LOCK"
    exit 0
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

# Unload the KeepAlive LaunchAgent first. Without this, the up-front kill below is
# futile: launchd respawns KeyPath within ThrottleInterval, and the respawned
# process is alive during the in-place re-sign — producing a crash report with
# SIGKILL (Code Signature Invalid) / Taskgated Invalid Signature. The agent is
# restored in cleanup() (runs on every exit path), so a failed deploy never leaves
# KeyPath disabled.
if launchctl print "${AGENT_DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
    AGENT_WAS_LOADED=1
    echo "⏸️  Unloading ${AGENT_LABEL} so launchd won't respawn KeyPath during signing..."
    launchctl bootout "${AGENT_DOMAIN}/${AGENT_LABEL}" 2>/dev/null || true
    for _ in {1..40}; do
        launchctl print "${AGENT_DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1 || break
        sleep 0.05
    done
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
    # Wait up to 6s for graceful shutdown
    for _ in {1..120}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.05
    done
    # Force-kill if still alive — proceeding with the process running causes
    # SIGKILL (Code Signature Invalid) when the replaced binary invalidates
    # mapped pages in the old process.
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "⚠️  $APP_NAME did not exit in time, sending SIGKILL..."
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
        sleep 0.2
    fi
fi

# Build debug (incremental). The default app scope keeps UI loops away from
# companion products that are irrelevant for visual iteration.
if [[ "$BUILD_SCOPE" == "app" ]]; then
    echo "🔨 Building KeyPath app product..."
    PRODUCT_FLAGS=(--product KeyPath)
else
    echo "🔨 Building full package..."
    PRODUCT_FLAGS=()
fi
BUILD_LOG="$BUILD_LOG_DIR/build-${BUILD_ID}.log"
write_build_log_header "$BUILD_LOG"
# Optional build-system override. Unset, or the legacy value "native", means use
# the toolchain default; SwiftPM now warns when passed --build-system native.
BUILD_SYSTEM_FLAGS=()
if [[ -n "${KEYPATH_BUILD_SYSTEM:-}" && "${KEYPATH_BUILD_SYSTEM:-}" != "native" ]]; then
    BUILD_SYSTEM_FLAGS=(--build-system "$KEYPATH_BUILD_SYSTEM")
fi
# ${arr[@]+...} guard: bash 3.2 under `set -u` treats expanding an empty array as unbound
if ! swift build --disable-automatic-resolution ${BUILD_SYSTEM_FLAGS[@]+"${BUILD_SYSTEM_FLAGS[@]}"} "${MODULE_CACHE_FLAGS[@]}" ${PRODUCT_FLAGS[@]+"${PRODUCT_FLAGS[@]}"} >> "$BUILD_LOG" 2>&1; then
    BUILD_END_MS=$(get_time_ms)
    DURATION=$((BUILD_END_MS - BUILD_START_MS))
    print_build_failure_diagnostics "$BUILD_LOG"
    log_build_event "BUILD_FAILED" "$DURATION"
    exit 1
fi

if ! BIN_DIR_OUTPUT=$(swift build --show-bin-path --disable-automatic-resolution ${BUILD_SYSTEM_FLAGS[@]+"${BUILD_SYSTEM_FLAGS[@]}"} "${MODULE_CACHE_FLAGS[@]}" 2>> "$BUILD_LOG"); then
    BUILD_END_MS=$(get_time_ms)
    DURATION=$((BUILD_END_MS - BUILD_START_MS))
    print_build_failure_diagnostics "$BUILD_LOG"
    log_build_event "SHOW_BIN_PATH_FAILED" "$DURATION"
    exit 1
fi
BIN_DIR=$(printf '%s\n' "$BIN_DIR_OUTPUT" | tail -1)
if [[ -z "$BIN_DIR" ]]; then
    BUILD_END_MS=$(get_time_ms)
    DURATION=$((BUILD_END_MS - BUILD_START_MS))
    echo "swift build --show-bin-path produced no output" >> "$BUILD_LOG"
    print_build_failure_diagnostics "$BUILD_LOG"
    log_build_event "SHOW_BIN_PATH_EMPTY" "$DURATION"
    exit 1
fi
tail -3 "$BUILD_LOG" || true
rm -f "$BUILD_LOG"

# Get the built binary
DEBUG_BIN="$BIN_DIR/KeyPath"
CLI_BIN="$BIN_DIR/keypath-cli"

if [[ ! -f "$DEBUG_BIN" ]]; then
    echo "❌ Build failed - binary not found"
    log_build_event "FAILED_NO_BINARY"
    exit 1
fi
if [[ "$BUILD_SCOPE" == "full" ]]; then
    if [[ ! -f "$CLI_BIN" ]]; then
        echo "❌ Build failed - CLI binary not found"
        log_build_event "FAILED_NO_CLI_BINARY"
        exit 1
    fi
else
    echo "ℹ️  Keeping the installed keypath-cli; set KEYPATH_QUICK_DEPLOY_BUILD_SCOPE=full to refresh it."
fi

# Copy binary to app bundle
echo "📦 Deploying..."
cp "$DEBUG_BIN" "$MACOS_DIR/$APP_NAME"
if [[ "$BUILD_SCOPE" == "full" && -f "$CLI_BIN" ]]; then
    cp "$CLI_BIN" "$MACOS_DIR/keypath-cli"
fi

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

# Ensure the kanata binary is present inside "Kanata Engine.app".
# Copy from the pre-built artifact if available.
KANATA_UNIVERSAL="$PROJECT_DIR/build/kanata-universal"
if [[ ! -f "$KANATA_ENGINE_MACOS/kanata" && -f "$KANATA_UNIVERSAL" ]]; then
    cp "$KANATA_UNIVERSAL" "$KANATA_ENGINE_MACOS/kanata"
    chmod 755 "$KANATA_ENGINE_MACOS/kanata"
fi

# Remove legacy symlink if present
OLD_KANATA="$APP_BUNDLE/Contents/Library/KeyPath/kanata"
rm -f "$OLD_KANATA"

if [[ ! -f "$KANATA_ENGINE_MACOS/kanata" ]]; then
    echo "❌ Kanata Engine.app has no kanata binary. Run ./Scripts/build-kanata.sh first."
    log_build_event "FAILED_NO_KANATA_BINARY"
    exit 1
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
if [[ "$BUILD_SCOPE" == "full" && -f "$KANATA_LAUNCHER_BIN" ]]; then
    mkdir -p "$(dirname "$KANATA_LAUNCHER_DST")"
    cp "$KANATA_LAUNCHER_BIN" "$KANATA_LAUNCHER_DST"
    chmod 755 "$KANATA_LAUNCHER_DST"
fi

# Rebuild the Rust host bridge only for full deploys or explicit opt-in. UI-only
# changes do not need to pay this cost on every cycle.
if [[ "$HOST_BRIDGE_MODE" == "1" ]]; then
    ./Scripts/build-kanata-host-bridge.sh >/dev/null
else
    echo "ℹ️  Skipping host bridge rebuild; set KEYPATH_QUICK_DEPLOY_HOST_BRIDGE=1 to refresh it."
fi

KANATA_HOST_BRIDGE_SRC="$PROJECT_DIR/build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib"
KANATA_HOST_BRIDGE_DST="$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"
if [[ "$HOST_BRIDGE_MODE" == "1" && -f "$KANATA_HOST_BRIDGE_SRC" ]]; then
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
if [[ -f "$MACOS_DIR/keypath-cli" ]] && ! otool -l "$MACOS_DIR/keypath-cli" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/keypath-cli" 2>/dev/null || true
fi
if [[ ! -f "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]]; then
    echo "❌ Sparkle.framework is missing from the deployed app bundle" >&2
    exit 1
fi
RPATH_EXECUTABLES=("$MACOS_DIR/$APP_NAME")
if [[ -f "$MACOS_DIR/keypath-cli" ]]; then
    RPATH_EXECUTABLES+=("$MACOS_DIR/keypath-cli")
fi
for executable in "${RPATH_EXECUTABLES[@]}"; do
    if ! otool -l "$executable" | grep -q "@executable_path/../Frameworks"; then
        echo "❌ $(basename "$executable") is missing @executable_path/../Frameworks rpath" >&2
        echo "   Without this, dyld cannot load the embedded Sparkle.framework at launch." >&2
        exit 1
    fi
done

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
HELPER_EXEC="$APP_BUNDLE/Contents/Library/HelperTools/KeyPathHelper"
HELPER_ENTITLEMENTS="$PROJECT_DIR/Sources/KeyPathHelper/KeyPathHelper.entitlements"
CLI_EXEC="$APP_BUNDLE/Contents/MacOS/keypath-cli"
LOCAL_CODESIGN_FLAGS=(--timestamp=none)

# Re-sign the embedded privileged helper with its REQUIRED signing identifier and
# re-seal the app afterwards. `codesign --deep` on the app re-signs nested
# executables with a filename-derived identifier ("KeyPathHelper"), but the app's
# SMPrivilegedExecutables entry requires identifier "com.keypath.helper". A mismatch
# makes the helper fail validation — the setup wizard reports a privileged-helper
# error it "can't fix". So after the --deep pass we re-sign the helper with the
# correct identifiers, then re-seal the OUTER app WITHOUT --deep so the corrected
# nested signatures are preserved. $1 = signing identity ("-" for ad-hoc).
resign_nested_identifiers() {
    local sign_id="$1"
    if [[ -f "$HELPER_EXEC" && -f "$HELPER_ENTITLEMENTS" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" \
            --identifier "com.keypath.helper" \
            --entitlements "$HELPER_ENTITLEMENTS" \
            --sign "$sign_id" \
            "$HELPER_EXEC" || echo "⚠️  Failed to re-sign helper with com.keypath.helper identifier"
    fi
    if [[ -f "$CLI_EXEC" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" \
            --identifier "com.keypath.KeyPath.CLI" \
            --sign "$sign_id" \
            "$CLI_EXEC" || echo "⚠️  Failed to re-sign keypath-cli with com.keypath.KeyPath.CLI identifier"
    fi
    codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$sign_id" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
}

if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    if [[ -f "$HELPER_EXEC" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" "$HELPER_EXEC" 2>/dev/null || true
    fi
    if [[ -d "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" || echo "⚠️  Failed to sign Kanata Engine kanata binary"
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/Kanata Engine.app" || echo "⚠️  Failed to sign Kanata Engine.app bundle"
    fi
    if [[ -f "$APP_BUNDLE/Contents/Library/KeyPath/kanata-launcher" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/kanata-launcher" 2>/dev/null || true
    fi
    if [[ -f "$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" 2>/dev/null || true
    fi
    if [[ -f "$APP_BUNDLE/Contents/MacOS/keypath-cli" ]]; then
        codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --identifier "com.keypath.KeyPath.CLI" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/MacOS/keypath-cli" 2>/dev/null || true
    fi
    codesign --force --options=runtime "${LOCAL_CODESIGN_FLAGS[@]}" --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE"
    resign_nested_identifiers "$SIGNING_IDENTITY"
else
    echo "⚠️  Developer ID identity not found; using ad-hoc signing (helper may reject this build)."
    codesign --force "${LOCAL_CODESIGN_FLAGS[@]}" --sign - --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE"
    resign_nested_identifiers "-"
fi

# Verify signature is valid before restarting — catch any silent corruption.
if ! codesign --verify --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "❌ Code signature verification failed after signing!"
    echo "   The app may crash with 'Code Signature Invalid' if launched."
    echo "   Try a full build: ./build.sh"
    log_build_event "SIGN_VERIFY_FAILED"
    exit 1
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
