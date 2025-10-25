#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -euo pipefail

# Verbose mode: VERBOSE=1 ./Scripts/build-and-sign.sh
if [[ "${VERBOSE:-0}" == "1" ]]; then set -x; fi

SCRIPT_START_TS=$(date +%s)
STEP_START_TS=$SCRIPT_START_TS

log() {
  printf "%s %s\n" "$(date '+%H:%M:%S')" "$*"
}

start_step() {
  STEP_START_TS=$(date +%s)
  log "▶ $*"
}

end_step() {
  local now=$(date +%s)
  local dur=$(( now - STEP_START_TS ))
  log "✓ Completed in ${dur}s"
}

# Run a long step with periodic heartbeats and a soft timeout
# Usage: run_with_heartbeat <label> <timeout_seconds> -- <cmd> [args...]
run_with_heartbeat() {
  local label="$1"; shift
  local limit="$1"; shift
  if [[ "$1" != "--" ]]; then
    echo "run_with_heartbeat: missing -- before command" >&2; return 99
  fi
  shift

  start_step "$label"
  local start_ts=$(date +%s)
  ( "$@" ) &
  local pid=$!
  local last_print=0
  while kill -0 $pid 2>/dev/null; do
    local now=$(date +%s)
    local elapsed=$(( now - start_ts ))
    if (( now - last_print >= 10 )); then
      # Print a heartbeat and a lightweight ps snapshot (if available)
      if command -v ps >/dev/null 2>&1; then
        local psline
        psline=$(ps -o pid=,pcpu=,etime=,rss= -p $pid 2>/dev/null | awk '{printf "pid=%s cpu=%s%% etime=%s rss=%sKB", $1,$2,$3,$4}') || psline="pid=$pid"
        log "… still working on: $label (elapsed ${elapsed}s) [$psline]"
      else
        log "… still working on: $label (elapsed ${elapsed}s)"
      fi
      last_print=$now
    fi
    if (( elapsed > limit )); then
      log "⛔ $label exceeded ${limit}s — terminating PID $pid"
      kill -TERM $pid 2>/dev/null || true
      sleep 2
      kill -KILL $pid 2>/dev/null || true
      wait $pid 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait $pid
  local rc=$?
  end_step
  return $rc
}

trap 'log "⛔ Build script aborted"' INT TERM

if [[ "${SKIP_KANATA_BUILD:-0}" == "1" ]]; then
  start_step "Skipping bundled kanata build (SKIP_KANATA_BUILD=1)"
  echo "ℹ️  Will reuse build/kanata-universal if present; otherwise continue without bundling."
  end_step
else
  start_step "Building bundled kanata (first run can take several minutes)"
  echo "🦀 Building bundled kanata..."
  # Build kanata from source (required for proper signing)
  ./Scripts/build-kanata.sh || {
    echo "⚠️  Kanata build failed or unavailable. Proceeding without bundling kanata." >&2
  }
  end_step
fi

echo "🏗️  Building KeyPath (release, no WMO)…"
# Build main app (disable whole-module optimization to avoid hang). Timeout: 10 minutes hard cap.
log "Running: swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization"
if ! run_with_heartbeat "Swift build (release)" 600 -- \
  swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization; then
  log "⚠️  Swift build hit timeout or failed; retrying with verbose output"
  run_with_heartbeat "Swift build retry (-v)" 600 -- \
    swift build -v --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization
fi

start_step "Creating app bundle"
echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Clean and create directories
rm -rf "$DIST_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$CONTENTS/Library/KeyPath"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy bundled kanata binary if available
if [ -f "build/kanata-universal" ]; then
  cp "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"
  echo "✅ Bundled kanata included"
else
  echo "⚠️  No bundled kanata found; app will expect system-installed kanata"
fi

# Copy main app Info.plist
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"

# Copy app icon
if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
    cp "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES/"
    echo "✅ Copied app icon"
else
    echo "⚠️ WARNING: AppIcon.icns not found"
fi

# Copy SPM resource bundles (contains screenshots and other resources)
if [ -d "$BUILD_DIR/KeyPath_KeyPath.bundle" ]; then
    cp -R "$BUILD_DIR/KeyPath_KeyPath.bundle" "$RESOURCES/"
    echo "✅ Copied KeyPath resource bundle"
else
    echo "⚠️ WARNING: KeyPath resource bundle not found"
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
end_step

start_step "Signing executables"
echo "✍️  Signing executables..."
# Detect signing identity if not provided
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "${SIGNING_IDENTITY}"; then
  echo "⚠️  Signing identity '${SIGNING_IDENTITY}' not found; falling back to ad-hoc signing" >&2
  SIGNING_IDENTITY="-" # ad-hoc
fi

# Sign bundled kanata binary (already signed in build-kanata.sh, but ensure consistency)
if [ -f "$CONTENTS/Library/KeyPath/kanata" ]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force -s - "$CONTENTS/Library/KeyPath/kanata" || true
  else
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata" || true
  fi
fi

# Sign main app WITH entitlements
ENTITLEMENTS_FILE="KeyPath.entitlements"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "⚠️  Using ad-hoc signing for app bundle (development only)"
  # Entitlements are ignored for ad-hoc; sign shallow to keep fast
  codesign --force -s - "$APP_BUNDLE" || true
else
  if [ -f "$ENTITLEMENTS_FILE" ]; then
      echo "Applying entitlements from $ENTITLEMENTS_FILE..."
      codesign --force --options=runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  else
      echo "⚠️ WARNING: No entitlements file found - admin operations may fail"
      codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  fi
fi
end_step

start_step "Verifying signatures"
echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"
end_step

start_step "Creating distribution archive"
echo "📦 Creating distribution archive..."
cd "$DIST_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
cd ..
end_step

if [[ "${SKIP_NOTARIZE:-0}" == "1" || "${CI:-false}" != "true" ]]; then
  start_step "Skipping notarization (SKIP_NOTARIZE=1 or not running in CI)"
  echo "ℹ️  Distribution zip is unsigned for notarization."
  end_step
else
  # Submit asynchronously, then poll to provide progress updates.
  start_step "Submitting for notarization (async)"
  echo "📋 Submitting for notarization..."
  SUBMIT_OUT=$(xcrun notarytool submit "${DIST_DIR}/${APP_NAME}.zip" --keychain-profile "KeyPath-Profile" --output-format json 2>/dev/null || true)
  REQUEST_ID=$(echo "$SUBMIT_OUT" | /usr/bin/python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("id",""))' 2>/dev/null || true)
  if [[ -z "$REQUEST_ID" ]]; then
    echo "❌ Notarization submission did not return an ID. Raw output:" >&2
    echo "$SUBMIT_OUT" >&2
    exit 2
  fi
  end_step

  # Poll up to 20 minutes with heartbeats
  start_step "Polling notarization status ($REQUEST_ID)"
  POLL_START=$(date +%s)
  while true; do
    STATUS_JSON=$(xcrun notarytool info "$REQUEST_ID" --keychain-profile "KeyPath-Profile" --output-format json 2>/dev/null || true)
    STATUS=$(echo "$STATUS_JSON" | /usr/bin/python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status",""))' 2>/dev/null || true)
    log "Notary status: ${STATUS:-unknown}"
    if [[ "$STATUS" == "Accepted" ]]; then
      break
    elif [[ "$STATUS" == "Invalid" || "$STATUS" == "Rejected" ]]; then
      echo "❌ Notarization failed: $STATUS_JSON" >&2
      exit 2
    fi
    if (( $(date +%s) - POLL_START > 1200 )); then
      echo "❌ Notarization polling exceeded 20 minutes." >&2
      exit 2
    fi
    sleep 15
  done
  end_step
fi

if [[ "${SKIP_NOTARIZE:-0}" == "1" || "${CI:-false}" != "true" ]]; then
  start_step "Skipping stapling (not notarized)"
  end_step
else
  start_step "Stapling notarization"
  echo "🔖 Stapling notarization..."
  xcrun stapler staple "$APP_BUNDLE"
  end_step
fi

start_step "Final verification"
echo "🎉 Build complete!"
echo "📍 Signed app: $APP_BUNDLE"
echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

echo "🔍 Final verification..."
spctl -a -vvv "$APP_BUNDLE"
end_step

start_step "Deploy to /Applications"
echo "✨ Ready for distribution!"

echo "📂 Deploying to /Applications..."
APP_DEST="/Applications/${APP_NAME}.app"
if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
fi
if ditto "$APP_BUNDLE" "$APP_DEST"; then
    echo "✅ Deployed latest $APP_NAME to $APP_DEST"
else
    echo "⚠️ WARNING: Failed to copy $APP_NAME to /Applications. You may need to rerun this step with sudo." >&2
fi

end_step

TOTAL_DUR=$(( $(date +%s) - SCRIPT_START_TS ))
log "🏁 All steps completed in ${TOTAL_DUR}s"
