#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
dest=${1:?output app path}
mkdir -p "$dest/Contents/MacOS"
cat > "$dest/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.keypath.experimental.permission-probe</string>
<key>CFBundleName</key><string>Permission Probe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>Disposable permission experiment.</string>
</dict></plist>
PLIST
plutil -replace CFBundleIdentifier -string "${PROBE_BUNDLE_ID:-com.keypath.experimental.permission-probe}" "$dest/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${PROBE_VERSION:-1}" "$dest/Contents/Info.plist"
clang -arch arm64 -mmacosx-version-min=15 -framework AppKit -framework ApplicationServices -framework IOKit -framework Carbon "$root/probe.m" -o "$dest/Contents/MacOS/probe"
codesign --force --sign "${PROBE_SIGN_IDENTITY:--}" "$dest"
codesign -dv --verbose=2 "$dest" 2>&1
shasum -a 256 "$dest/Contents/MacOS/probe"
