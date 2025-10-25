#!/bin/bash

# Fast local build + deploy for development
# - Debug config build for speed
# - Packages a minimal .app bundle into dist/KeyPath.app
# - Signs with Developer ID if available, otherwise ad-hoc
# - Skips notarization and Gatekeeper verification
# - Deploys to /Applications and launches the app

set -euo pipefail

if [[ "${VERBOSE:-0}" == "1" ]]; then set -x; fi

SCRIPT_START_TS=$(date +%s)
STEP_START_TS=$SCRIPT_START_TS

log() { printf "%s %s\n" "$(date '+%H:%M:%S')" "$*"; }
start_step() { STEP_START_TS=$(date +%s); log "▶ $*"; }
end_step() { local now=$(date +%s); log "✓ Completed in $(( now - STEP_START_TS ))s"; }

APP_NAME="KeyPath"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

INSTALL_PATH="${APP_DEST:-/Applications/${APP_NAME}.app}"
LAUNCH_APP="${LAUNCH_APP:-1}"

trap 'log "⛔ build-dev-local aborted"' INT TERM

start_step "Building $APP_NAME (debug)"
swift build -c debug --product "$APP_NAME"
end_step

start_step "Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CONTENTS/Library/KeyPath"

ARCH=$(uname -m)
EXEC_PATH=".build/${ARCH}-apple-macosx/debug/${APP_NAME}"
[[ -f "$EXEC_PATH" ]] || EXEC_PATH=".build/debug/${APP_NAME}"
cp "$EXEC_PATH" "$MACOS_DIR/$APP_NAME"

# Info.plist
if [[ -f "Sources/KeyPath/Info.plist" ]]; then
  cp "Sources/KeyPath/Info.plist" "$CONTENTS/"
else
  cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.keypath.KeyPath</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF
fi

# Icon
[[ -f "Sources/KeyPath/Resources/AppIcon.icns" ]] && cp "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES_DIR/"

# SPM resource bundle (debug)
BUILD_BUNDLE=".build/${ARCH}-apple-macosx/debug/KeyPath_KeyPath.bundle"
[[ -d "$BUILD_BUNDLE" ]] && cp -R "$BUILD_BUNDLE" "$RESOURCES_DIR/" || true

# Optional bundled kanata if present (skip heavy build here)
[[ -f build/kanata-universal ]] && cp build/kanata-universal "$CONTENTS/Library/KeyPath/kanata" || true

end_step

start_step "Signing (Developer ID if available; fallback ad-hoc)"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
if security find-identity -p codesigning -v 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
  if [[ -f "$CONTENTS/Library/KeyPath/kanata" ]]; then
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata" || true
  fi
  if [[ -f "KeyPath.entitlements" ]]; then
    codesign --force --options=runtime --entitlements KeyPath.entitlements --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  else
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  fi
else
  log "⚠️  Developer ID not found; using ad-hoc signing for local run"
  codesign --force -s - "$APP_BUNDLE" || true
fi
end_step

start_step "Deploy to /Applications"
ditto -v "$APP_BUNDLE" "$INSTALL_PATH"
# Clear quarantine to avoid notarization prompts during local dev
xattr -dr com.apple.quarantine "$INSTALL_PATH" || true
end_step

if [[ "$LAUNCH_APP" == "1" ]]; then
  start_step "Launch app"
  open -a "$INSTALL_PATH"
  end_step
fi

log "🎉 Done. Installed to: $INSTALL_PATH"

