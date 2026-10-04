#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
TEAM_ID="X2RKZ5TG99"
DEVELOPER_ID_AUTHORITY="Developer ID Application: Micah Alpern (${TEAM_ID})"
KANATA_ENGINE_ID="com.keypath.kanata-engine"
KANATA_ENGINE_REQ='identifier "com.keypath.kanata-engine" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'
APP_ID="com.keypath.KeyPath"
APP_REQ='identifier "com.keypath.KeyPath" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'
CLI_ID="com.keypath.KeyPath.CLI"
CLI_REQ='identifier "com.keypath.KeyPath.CLI" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'
BRIDGE_ID="com.keypath.kanata-host-bridge"
BRIDGE_REQ='identifier "com.keypath.kanata-host-bridge" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'
SIMULATOR_ID="com.keypath.kanata-simulator"
SIMULATOR_REQ='identifier "com.keypath.kanata-simulator" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'
MODE="source"
APP_PATH=""

usage() {
    cat <<'EOF'
Usage: Scripts/verify-identity-contract.sh [--source] [--payload-only PATH] [--app PATH]

Verifies the driverless packaging boundary and the stable Developer ID
identities of KeyPath, its CLI, Kanata Engine, simulator, and host bridge.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) MODE="source"; APP_PATH="" ;;
        --payload-only)
            MODE="payload"
            APP_PATH="${2:-}"
            if [[ -z "$APP_PATH" ]]; then echo "Missing path after --payload-only" >&2; usage >&2; exit 2; fi
            shift
            ;;
        --app)
            MODE="app"
            APP_PATH="${2:-}"
            if [[ -z "$APP_PATH" ]]; then echo "Missing path after --app" >&2; usage >&2; exit 2; fi
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

failures=0
pass() { echo "[identity-contract] PASS: $1"; }
fail() { failures=$((failures + 1)); echo "[identity-contract] FAIL: $1" >&2; }
expect_file() {
    if [[ -e "$1" ]]; then pass "$2 exists"; else fail "$2 missing at $1"; fi
}
expect_absent() {
    if [[ -e "$1" ]]; then fail "$2 unexpectedly exists at $1"; else pass "$2 absent"; fi
}
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
expect_plist_value() {
    local actual
    actual=$(plist_value "$1" "$2")
    if [[ "$actual" == "$3" ]]; then pass "$4 is $3"; else fail "$4 expected '$3' but found '${actual:-<missing>}' in $1"; fi
}
expect_codesign_identity() {
    local path=$1 expected_identifier=$2 expected_requirement=$3 description=$4 output actual_requirement
    if ! output=$(codesign -d -r- --verbose=4 "$path" 2>&1); then fail "$description codesign inspection failed: $output"; return; fi
    grep -F "Identifier=${expected_identifier}" <<<"$output" >/dev/null && pass "$description identifier is $expected_identifier" || fail "$description identifier is not $expected_identifier"
    grep -F "Authority=${DEVELOPER_ID_AUTHORITY}" <<<"$output" >/dev/null && pass "$description signed by ${DEVELOPER_ID_AUTHORITY}" || fail "$description lacks expected Developer ID authority"
    grep -F "TeamIdentifier=${TEAM_ID}" <<<"$output" >/dev/null && pass "$description team identifier is ${TEAM_ID}" || fail "$description team identifier is not ${TEAM_ID}"
    grep -E '^CodeDirectory .*flags=.*\(runtime\)' <<<"$output" >/dev/null && pass "$description uses hardened runtime" || fail "$description is not signed with hardened runtime"
    actual_requirement=$(sed -n 's/^designated => //p' <<<"$output" | tail -n 1)
    if [[ -z "$actual_requirement" ]]; then fail "$description designated requirement could not be parsed"; elif [[ "$actual_requirement" == "$expected_requirement" ]]; then pass "$description designated requirement is stable"; else fail "$description designated requirement changed: '$actual_requirement'"; fi
}
expect_no_forbidden_payloads() {
    local root=$1 found=0 path
    if [[ ! -d "$root/Contents" ]]; then
        fail "app Contents directory missing at $root/Contents"
        return
    fi
    local main_info="$root/Contents/Info.plist"
    if [[ ! -f "$main_info" ]]; then
        fail "main app Info.plist missing at $main_info"
        found=1
    elif ! plutil -lint "$main_info" >/dev/null 2>&1; then
        fail "main app Info.plist is invalid at $main_info"
        found=1
    elif /usr/libexec/PlistBuddy -c 'Print :SMPrivilegedExecutables' "$main_info" >/dev/null 2>&1; then
        fail "SMPrivilegedExecutables remains in packaged main app Info.plist"
        found=1
    else
        pass "packaged main app Info.plist omits SMPrivilegedExecutables"
    fi
    for path in "$root"/Contents/Library/HelperTools "$root"/Contents/Library/LaunchDaemons; do
        if [[ -e "$path" ]]; then fail "forbidden privileged packaging directory exists: $path"; found=1; fi
    done
    while IFS= read -r -d '' path; do fail "forbidden packaged driver/helper asset exists: $path"; found=1; done < <(
        find "$root/Contents" \( -name 'KeyPathHelper' -o -name 'com.keypath.helper.plist' -o -name 'com.keypath.kanata.plist' -o -name 'Karabiner-DriverKit-VirtualHIDDevice-*.pkg' -o -name 'uninstall.sh' -o -name 'kanata-launcher' \) -print0
    )
    [[ $found -eq 0 ]] && pass "no helper, launch daemon, launcher, Karabiner pkg, or uninstall script packaged"
}

verify_payload_only_contract() {
    if [[ ! -d "$APP_PATH" ]]; then
        fail "KeyPath.app artifact missing at $APP_PATH"
        return
    fi
    expect_no_forbidden_payloads "$APP_PATH"
}

verify_source_contract() {
    cd "$PROJECT_DIR"
    expect_plist_value "Sources/KeyPathApp/Resources/KanataEngine-Info.plist" "CFBundleIdentifier" "$KANATA_ENGINE_ID" "Kanata Engine bundle ID"
    expect_plist_value "Sources/KeyPathApp/Resources/KanataEngine-Info.plist" "CFBundleExecutable" "kanata" "Kanata Engine executable"
    if /usr/libexec/PlistBuddy -c 'Print :SMPrivilegedExecutables' Sources/KeyPathApp/Info.plist >/dev/null 2>&1; then fail "SMPrivilegedExecutables remains in main app Info.plist"; else pass "SMPrivilegedExecutables absent from main app Info.plist"; fi
    expect_absent "Sources/KeyPathApp/Resources/Karabiner-DriverKit-VirtualHIDDevice-8.0.0.pkg" "bundled Karabiner DriverKit installer"
    expect_absent "Sources/KeyPathApp/Resources/uninstall.sh" "privileged uninstall script"
    for file in Scripts/build-and-sign.sh Scripts/verify-identity-contract.sh Scripts/verify-release-signing-contract.sh; do
        [[ -f "$file" ]] && pass "$file exists" || fail "$file missing"
    done
}

verify_app_contract() {
    local app=$APP_PATH
    if [[ ! -d "$app" ]]; then fail "KeyPath.app artifact missing at $app"; return; fi
    local contents="$app/Contents"
    local engine="$contents/Library/KeyPath/Kanata Engine.app"
    local engine_binary="$engine/Contents/MacOS/kanata"
    local cli="$contents/MacOS/keypath-cli"
    local bridge="$contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"
    local simulator="$contents/Library/KeyPath/kanata-simulator"
    expect_file "$engine_binary" "Kanata Engine binary"
    expect_file "$cli" "bundled keypath-cli"
    expect_file "$bridge" "Kanata host bridge"
    expect_file "$simulator" "Kanata simulator"
    expect_file "$contents/Frameworks/Sparkle.framework" "Sparkle framework"
    expect_file "$contents/PlugIns/Insights.bundle/Contents/MacOS/libKeyPathInsights" "Insights plugin"
    expect_plist_value "$engine/Contents/Info.plist" "CFBundleIdentifier" "$KANATA_ENGINE_ID" "Kanata Engine bundle ID"
    expect_no_forbidden_payloads "$app"
    expect_codesign_identity "$app" "$APP_ID" "$APP_REQ" "KeyPath.app"
    expect_codesign_identity "$cli" "$CLI_ID" "$CLI_REQ" "keypath-cli"
    expect_codesign_identity "$engine" "$KANATA_ENGINE_ID" "$KANATA_ENGINE_REQ" "Kanata Engine.app"
    expect_codesign_identity "$engine_binary" "$KANATA_ENGINE_ID" "$KANATA_ENGINE_REQ" "Kanata Engine binary"
    expect_codesign_identity "$bridge" "$BRIDGE_ID" "$BRIDGE_REQ" "Kanata host bridge"
    expect_codesign_identity "$simulator" "$SIMULATOR_ID" "$SIMULATOR_REQ" "Kanata simulator"
}

case "$MODE" in
    source) verify_source_contract ;;
    payload) verify_payload_only_contract ;;
    app) verify_app_contract ;;
esac
if (( failures > 0 )); then echo "[identity-contract] ${failures} failure(s)" >&2; exit 1; fi
echo "[identity-contract] all checks passed"
