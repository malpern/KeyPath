#!/usr/bin/env bash
set -euo pipefail

# KeyPath helper diagnostics (no root required)
# Usage: Scripts/diagnose-helper.sh [/Applications/KeyPath.app]

APP_PATH=${1:-/Applications/KeyPath.app}
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EMBEDDED_HELPER="$APP_PATH/Contents/Library/HelperTools/KeyPathHelper"
EMBEDDED_PLIST="$APP_PATH/Contents/Library/LaunchDaemons/com.keypath.helper.plist"

BUILD_DIR_PATTERNS=("/dist/" "/.build/" "/build/" "/DerivedData/")

ts() { date +"%Y-%m-%d %H:%M:%S"; }
header() { echo; echo "==== $1 ===="; }

filter_build_dirs() {
  local path
  while IFS= read -r path; do
    local skip=0
    for pattern in "${BUILD_DIR_PATTERNS[@]}"; do
      if [[ "$path" == *"$pattern"* ]]; then
        skip=1
        break
      fi
    done
    if [[ $skip -eq 0 ]]; then
      echo "$path"
    fi
  done
}

list_app_copies() {
  if command -v mdfind >/dev/null 2>&1; then
    mdfind "kMDItemFSName == 'KeyPath.app'c" 2>/dev/null | filter_build_dirs | sort -u
  fi
}

extract_program_from_launchctl() {
  local label="$1"
  /bin/launchctl print "system/$label" 2>/dev/null \
    | awk -F'= ' '/program =/ {print $2; exit} /program identifier/ {print $2; exit}' \
    | sed -E 's/ \(mode:.*\)$//'
}

echo "[$(ts)] KeyPath helper diagnostics"
echo "App: $APP_PATH"

header "App copies (Spotlight)"
COPIES=$(list_app_copies || true)
if [[ -n "${COPIES:-}" ]]; then
  echo "$COPIES" | sed 's/^/  - /'
else
  echo "  (no Spotlight results; ensure app is in /Applications)"
fi

header "Presence checks"
[[ -f "$EMBEDDED_HELPER" ]] && echo "Helper exists: $EMBEDDED_HELPER" || echo "Helper missing: $EMBEDDED_HELPER"
[[ -f "$EMBEDDED_PLIST" ]] && echo "Daemon plist exists: $EMBEDDED_PLIST" || echo "Daemon plist missing: $EMBEDDED_PLIST"
[[ -f "$INFO_PLIST" ]] && echo "Info.plist exists: $INFO_PLIST" || echo "Info.plist missing: $INFO_PLIST"

header "App codesign summary"
if codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/  /'; then :; else echo "(codesign failed for app)"; fi

header "App codesign verify"
if codesign --verify --deep --strict --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/  /'; then
  echo "  ✅ App signature valid"
else
  echo "  ❌ App signature invalid"
fi

header "Signing identities (local keychain)"
if security find-identity -v -p codesigning 2>&1 | sed 's/^/  /'; then :; else echo "  (unable to query identities)"; fi

header "Helper codesign summary"
if codesign -dv --verbose=4 "$EMBEDDED_HELPER" 2>&1 | sed 's/^/  /'; then :; else echo "(codesign failed for helper)"; fi

header "Helper codesign verify"
if codesign --verify --strict --verbose=4 "$EMBEDDED_HELPER" 2>&1 | sed 's/^/  /'; then
  echo "  ✅ Helper signature valid"
else
  echo "  ❌ Helper signature invalid"
fi

header "Extract SMPrivilegedExecutables requirement"
REQ=$( /usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:com.keypath.helper" "$INFO_PLIST" 2>/dev/null || true )
if [[ -n "$REQ" ]]; then
  echo "Requirement:"; echo "$REQ" | sed 's/^/  /'
else
  echo "SMPrivilegedExecutables[com.keypath.helper] not found in Info.plist"
fi

if [[ -n "$REQ" ]]; then
  REQ_STRIPPED=$(printf "%s" "$REQ" | perl -pe 's#/\\*.*?\\*/##g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
  if [[ "$REQ_STRIPPED" != "$REQ" ]]; then
    echo "Sanitized requirement:"; echo "$REQ_STRIPPED" | sed 's/^/  /'
  fi
  header "Verify helper against requirement"
  DESIGNATED=$( /usr/bin/codesign -d -r- "$EMBEDDED_HELPER" 2>&1 | sed -n 's/^designated => //p' | head -n 1 )
  if [[ -n "$DESIGNATED" ]]; then
    DESIGNATED_STRIPPED=$(printf "%s" "$DESIGNATED" | perl -pe 's#/\\*.*?\\*/##g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    echo "Helper designated requirement:"; echo "$DESIGNATED" | sed 's/^/  /'
    if [[ "$DESIGNATED_STRIPPED" == "$REQ_STRIPPED" ]]; then
      echo "  ✅ Helper requirement matches SMPrivilegedExecutables"
    else
      echo "  ❌ Helper requirement does NOT match SMPrivilegedExecutables"
    fi
  else
    echo "  ❌ Could not extract helper designated requirement"
  fi
fi

header "BundleProgram path from embedded plist"
BUNDLE_PROGRAM=""
if [[ -f "$EMBEDDED_PLIST" ]]; then
  BUNDLE_PROGRAM=$( /usr/libexec/PlistBuddy -c "Print :BundleProgram" "$EMBEDDED_PLIST" 2>/dev/null || true )
  echo "BundleProgram: ${BUNDLE_PROGRAM:-<unset>}"
  if [[ -n "$BUNDLE_PROGRAM" ]]; then
    RESOLVED="$APP_PATH/$BUNDLE_PROGRAM"
    echo "Resolved path: $RESOLVED"
    [[ -f "$RESOLVED" ]] && echo "  ✅ Exists" || echo "  ❌ Missing"
  fi
fi

header "launchctl disabled state (best-effort)"
if /bin/launchctl print-disabled system 2>/dev/null | egrep -i "keypath" | sed 's/^/  /'; then :; else echo "  (no keypath entries or insufficient privileges)"; fi

header "launchctl state (best-effort)"
for label in com.keypath.helper com.keypath.KeyPath.helper; do
  echo "-- $label"
  if /bin/launchctl print "system/$label" 2>&1 | sed 's/^/  /'; then :; else echo "  (no launchctl record or insufficient privileges)"; fi

done

header "launchctl program mismatch check"
if [[ -n "$BUNDLE_PROGRAM" ]]; then
  EXPECTED="$APP_PATH/$BUNDLE_PROGRAM"
  ACTUAL=$(extract_program_from_launchctl "com.keypath.helper")
  if [[ -n "${ACTUAL:-}" ]]; then
    echo "Expected: $EXPECTED"
    echo "Actual:   $ACTUAL"
    if [[ "$ACTUAL" == /* ]]; then
      if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "⚠️  Mismatch: launchd points at a different absolute path"
      fi
    else
      if [[ "$ACTUAL" != "$BUNDLE_PROGRAM" ]]; then
        echo "⚠️  Mismatch: launchd points at a different bundle-relative path"
      fi
    fi
  else
    echo "(could not extract program from launchctl output)"
  fi
fi

echo; echo "[$(ts)] Done"
