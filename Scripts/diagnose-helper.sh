#!/usr/bin/env bash
set -euo pipefail

# KeyPath helper diagnostics (no root required)
# Usage: Scripts/diagnose-helper.sh [/Applications/KeyPath.app]

APP_PATH=${1:-/Applications/KeyPath.app}
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EMBEDDED_HELPER="$APP_PATH/Contents/Library/HelperTools/KeyPathHelper"
EMBEDDED_PLIST="$APP_PATH/Contents/Library/LaunchDaemons/com.keypath.helper.plist"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
header() { echo; echo "==== $1 ===="; }

echo "[$(ts)] KeyPath helper diagnostics"
echo "App: $APP_PATH"

header "Presence checks"
[[ -f "$EMBEDDED_HELPER" ]] && echo "Helper exists: $EMBEDDED_HELPER" || echo "Helper missing: $EMBEDDED_HELPER"
[[ -f "$EMBEDDED_PLIST" ]] && echo "Daemon plist exists: $EMBEDDED_PLIST" || echo "Daemon plist missing: $EMBEDDED_PLIST"
[[ -f "$INFO_PLIST" ]] && echo "Info.plist exists: $INFO_PLIST" || echo "Info.plist missing: $INFO_PLIST"

header "App codesign summary"
if codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/  /'; then :; else echo "(codesign failed for app)"; fi

header "Helper codesign summary"
if codesign -dv --verbose=4 "$EMBEDDED_HELPER" 2>&1 | sed 's/^/  /'; then :; else echo "(codesign failed for helper)"; fi

header "Extract SMPrivilegedExecutables requirement"
REQ=$( /usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:com.keypath.helper" "$INFO_PLIST" 2>/dev/null || true )
if [[ -n "$REQ" ]]; then
  echo "Requirement:"; echo "$REQ" | sed 's/^/  /'
else
  echo "SMPrivilegedExecutables[com.keypath.helper] not found in Info.plist"
fi

if [[ -n "$REQ" ]]; then
  header "Verify helper against requirement"
  if codesign -vv --strict -R "$REQ" "$EMBEDDED_HELPER" 2>&1 | sed 's/^/  /'; then
    echo "  ✅ Helper satisfies SMPrivilegedExecutables requirement"
  else
    echo "  ❌ Helper does NOT satisfy SMPrivilegedExecutables requirement"
  fi
fi

header "BundleProgram path from embedded plist"
if [[ -f "$EMBEDDED_PLIST" ]]; then
  BUNDLE_PROGRAM=$( /usr/libexec/PlistBuddy -c "Print :BundleProgram" "$EMBEDDED_PLIST" 2>/dev/null || true )
  echo "BundleProgram: ${BUNDLE_PROGRAM:-<unset>}"
  if [[ -n "$BUNDLE_PROGRAM" ]]; then
    RESOLVED="$APP_PATH/$BUNDLE_PROGRAM"
    echo "Resolved path: $RESOLVED"
    [[ -f "$RESOLVED" ]] && echo "  ✅ Exists" || echo "  ❌ Missing"
  fi
fi

header "launchctl state (best-effort)"
if /bin/launchctl print system/com.keypath.helper 2>&1 | sed 's/^/  /'; then :; else echo "  (no launchctl record or insufficient privileges)"; fi

echo; echo "[$(ts)] Done"

