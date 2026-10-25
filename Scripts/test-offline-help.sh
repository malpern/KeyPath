#!/bin/bash
# Build a standalone Help-only app. Never install or start the KeyPath runtime.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/.build/offline-help-qa"}
APP="$OUTPUT/OfflineHelpQA.app"
rm -f "$OUTPUT/offline-report.json"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
python3 "$ROOT/Scripts/build-offline-help.py" --output "$APP/Contents/Resources/OfflineHelp"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.keypath.offline-help-qa</string><key>CFBundleName</key><string>OfflineHelpQA</string><key>CFBundleExecutable</key><string>OfflineHelpQA</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library \
  "$ROOT/Sources/KeyPathAppKit/UI/Help/OfflineHelpStore.swift" \
  "$ROOT/Sources/KeyPathAppKit/UI/Help/WebHelpView.swift" \
  "$ROOT/Scripts/verify-offline-help.swift" -o "$APP/Contents/MacOS/OfflineHelpQA"
echo "Open $APP to run the fresh offline WebKit checks; results: $OUTPUT/offline-report.json"
