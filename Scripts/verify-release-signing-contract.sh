#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

failures=0

fail() {
    failures=$((failures + 1))
    echo "❌ $1" >&2
}

pass() {
    echo "✅ $1"
}

require_file() {
    local path=$1
    if [[ -f "$PROJECT_DIR/$path" ]]; then
        pass "$path exists"
    else
        fail "$path is missing"
    fi
}

require_executable() {
    local path=$1
    if [[ -x "$PROJECT_DIR/$path" ]]; then
        pass "$path is executable"
    else
        fail "$path must be executable"
    fi
}

require_contains() {
    local path=$1
    local needle=$2
    local reason=$3
    if grep -Fq -- "$needle" "$PROJECT_DIR/$path"; then
        pass "$reason"
    else
        fail "$path missing required text for: $reason"
        echo "   expected: $needle" >&2
    fi
}

require_plist_key() {
    local path=$1
    local key=$2
    local expected=$3
    local actual
    if ! actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PROJECT_DIR/$path" 2>/dev/null); then
        fail "$path missing entitlement key: $key"
        return
    fi
    if [[ "$actual" == "$expected" ]]; then
        pass "$path pins $key = $expected"
    else
        fail "$path expected $key = $expected, got $actual"
    fi
}

require_valid_plist() {
    local path=$1
    if plutil -lint "$PROJECT_DIR/$path" >/dev/null; then
        pass "$path is a valid plist"
    else
        fail "$path is not a valid plist"
    fi
}

usage() {
    cat <<'EOF'
Usage: Scripts/verify-release-signing-contract.sh [--source]

Validate the source-level release signing contract before build/sign/notarize:
- entitlements files are valid plists with the expected baseline keys
- release signing commands use hardened runtime, stable identifiers, and entitlements
- release-doctor/build-and-sign run the identity and signing-contract gates
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$PROJECT_DIR"

require_file "KeyPath.entitlements"
require_file "Sources/KeyPathHelper/KeyPathHelper.entitlements"
require_file "kanata.entitlements"
require_file "Scripts/build-and-sign.sh"
require_file "Scripts/release-doctor.sh"
require_executable "Scripts/verify-release-signing-contract.sh"

for plist in \
    "KeyPath.entitlements" \
    "Sources/KeyPathHelper/KeyPathHelper.entitlements" \
    "kanata.entitlements"; do
    require_valid_plist "$plist"
done

require_plist_key "KeyPath.entitlements" "com.apple.security.app-sandbox" "false"
require_plist_key "KeyPath.entitlements" "com.apple.security.network.client" "true"
require_plist_key "KeyPath.entitlements" "com.apple.security.automation.apple-events" "true"
require_plist_key "Sources/KeyPathHelper/KeyPathHelper.entitlements" "com.apple.security.app-sandbox" "false"
require_plist_key "kanata.entitlements" "com.apple.security.device.hid" "true"
require_plist_key "kanata.entitlements" "com.apple.security.device.input-monitoring" "true"

build_script="Scripts/build-and-sign.sh"
doctor_script="Scripts/release-doctor.sh"

require_contains "$build_script" 'HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"' "helper entitlements source is explicit"
require_contains "$build_script" '--identifier "com.keypath.helper"' "helper signing uses stable helper identifier"
require_contains "$build_script" '--entitlements "$HELPER_ENTITLEMENTS"' "helper signing applies helper entitlements"
require_contains "$build_script" 'ENTITLEMENTS_FILE="KeyPath.entitlements"' "main app entitlements source is explicit"
require_contains "$build_script" '--entitlements "$ENTITLEMENTS_FILE"' "main app signing applies app entitlements"
require_contains "$build_script" '--identifier "com.keypath.KeyPath.CLI"' "CLI signing uses helper-trusted stable identifier"
require_contains "$build_script" '--force --options=runtime' "release signing uses hardened runtime"
require_contains "$build_script" 'kp_sign "$CONTENTS/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata" --force --options=runtime --sign "$SIGNING_IDENTITY"' "Kanata Engine inner binary is hardened-runtime signed"
require_contains "$build_script" 'kp_sign "$CONTENTS/Library/KeyPath/Kanata Engine.app" --force --options=runtime --sign "$SIGNING_IDENTITY"' "Kanata Engine bundle is hardened-runtime signed"
require_contains "$build_script" 'kp_sign "$CONTENTS/Library/KeyPath/kanata-launcher" --force --options=runtime --sign "$SIGNING_IDENTITY"' "Kanata launcher is hardened-runtime signed"
require_contains "$build_script" 'kp_sign "$CONTENTS/Library/KeyPath/libkeypath_kanata_host_bridge.dylib" --force --options=runtime --sign "$SIGNING_IDENTITY"' "Kanata host bridge is hardened-runtime signed"
require_contains "$build_script" 'kp_sign "$CONTENTS/Library/KeyPath/kanata-simulator" --force --options=runtime --sign "$SIGNING_IDENTITY"' "Kanata simulator is hardened-runtime signed"
require_contains "$build_script" '"$SCRIPT_DIR/verify-identity-contract.sh" --app "$APP_BUNDLE"' "build-and-sign runs installed-app identity verification"
require_contains "$build_script" '"$SCRIPT_DIR/verify-release-signing-contract.sh" --source' "build-and-sign runs source signing-contract verification"
require_contains "$doctor_script" 'verify-release-signing-contract.sh" --source' "release-doctor runs source signing-contract verification"

if (( failures > 0 )); then
    echo "❌ Release signing contract failed with $failures issue(s)." >&2
    exit 1
fi

echo "✅ Release signing contract passed."
