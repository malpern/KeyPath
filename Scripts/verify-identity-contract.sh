#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

TEAM_ID="X2RKZ5TG99"
DEVELOPER_ID_AUTHORITY="Developer ID Application: Micah Alpern (${TEAM_ID})"

KANATA_ENGINE_ID="com.keypath.kanata-engine"
KANATA_ENGINE_REQ='identifier "com.keypath.kanata-engine" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'

HELPER_ID="com.keypath.helper"
HELPER_REQ='identifier "com.keypath.helper" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'

KANATA_DAEMON_ID="com.keypath.kanata"
KANATA_LAUNCHER_ID="kanata-launcher"
KANATA_LAUNCHER_REQ='identifier "kanata-launcher" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99'

MODE="source"
APP_PATH=""

usage() {
    cat <<'EOF'
Usage: Scripts/verify-identity-contract.sh [--source] [--app PATH]

Verifies the Workstream 4 identity-stability contract for KeyPath's
permission-bearing and launchd-managed components.

Modes:
  --source    Verify committed plists/constants only. Used by release-doctor and CI.
  --app PATH  Verify a signed KeyPath.app artifact, including codesign identities.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            MODE="source"
            APP_PATH=""
            ;;
        --app)
            MODE="app"
            APP_PATH="${2:-}"
            if [[ -z "$APP_PATH" ]]; then
                echo "Missing path after --app" >&2
                usage >&2
                exit 2
            fi
            shift
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

failures=0

pass() {
    echo "[identity-contract] PASS: $1"
}

fail() {
    failures=$((failures + 1))
    echo "[identity-contract] FAIL: $1" >&2
}

plist_value() {
    local plist=$1
    local key_path=$2
    /usr/libexec/PlistBuddy -c "Print :${key_path}" "$plist" 2>/dev/null || true
}

expect_file() {
    local path=$1
    local description=$2
    if [[ -e "$path" ]]; then
        pass "$description exists"
    else
        fail "$description missing at $path"
    fi
}

expect_plist_value() {
    local plist=$1
    local key_path=$2
    local expected=$3
    local description=$4
    local actual
    actual=$(plist_value "$plist" "$key_path")
    if [[ "$actual" == "$expected" ]]; then
        pass "$description is $expected"
    else
        fail "$description expected '$expected' but found '${actual:-<missing>}' in $plist"
    fi
}

expect_text() {
    local file=$1
    local needle=$2
    local description=$3
    if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description missing '$needle' in $file"
    fi
}

expect_codesign_identity() {
    local path=$1
    local expected_identifier=$2
    local expected_requirement=$3
    local description=$4
    local output
    if ! output=$(codesign -d -r- --verbose=4 "$path" 2>&1); then
        fail "$description codesign inspection failed: $output"
        return
    fi

    if grep -F "Identifier=${expected_identifier}" <<<"$output" >/dev/null; then
        pass "$description signing identifier is $expected_identifier"
    else
        fail "$description signing identifier is not $expected_identifier"
    fi

    if grep -F "Authority=${DEVELOPER_ID_AUTHORITY}" <<<"$output" >/dev/null; then
        pass "$description signed by ${DEVELOPER_ID_AUTHORITY}"
    else
        fail "$description is not signed by ${DEVELOPER_ID_AUTHORITY}"
    fi

    if grep -F "TeamIdentifier=${TEAM_ID}" <<<"$output" >/dev/null; then
        pass "$description team identifier is ${TEAM_ID}"
    else
        fail "$description team identifier is not ${TEAM_ID}"
    fi

    local actual_requirement
    actual_requirement=$(sed -n 's/^designated => //p' <<<"$output" | tail -n 1)
    if [[ -z "$actual_requirement" ]]; then
        fail "$description designated requirement could not be parsed from codesign output; codesign output format may have changed"
        return
    fi

    if [[ "$actual_requirement" == "$expected_requirement" ]]; then
        pass "$description designated requirement is stable"
    else
        fail "$description designated requirement changed. Expected '$expected_requirement' but found '$actual_requirement'"
    fi
}

verify_source_contract() {
    cd "$PROJECT_DIR"

    local kanata_info="Sources/KeyPathApp/Resources/KanataEngine-Info.plist"
    local kanata_plist="Sources/KeyPathApp/com.keypath.kanata.plist"
    local helper_info="Sources/KeyPathHelper/Info.plist"
    local helper_plist="Sources/KeyPathHelper/com.keypath.helper.plist"

    expect_plist_value "$kanata_info" "CFBundleIdentifier" "$KANATA_ENGINE_ID" "Kanata Engine bundle ID"
    expect_plist_value "$kanata_info" "CFBundleExecutable" "kanata" "Kanata Engine executable"
    expect_text "Sources/KeyPathCore/KanataRuntimeHost.swift" 'Kanata Engine.app' "Kanata Engine bundle path is modeled"
    expect_text "Sources/KeyPathCore/KanataRuntimeHost.swift" 'Contents/MacOS/kanata' "Kanata canonical bundled binary path is modeled"
    expect_text "Sources/KeyPathCore/KeyPathConstants.swift" "public static let kanataEngineBundleID = \"$KANATA_ENGINE_ID\"" "Kanata Engine bundle ID constant is pinned"

    expect_plist_value "$helper_info" "CFBundleIdentifier" "$HELPER_ID" "privileged helper bundle ID"
    expect_plist_value "$helper_plist" "Label" "$HELPER_ID" "privileged helper launchd label"
    expect_plist_value "$helper_plist" "BundleProgram" "Contents/Library/HelperTools/KeyPathHelper" "privileged helper BundleProgram"
    expect_plist_value "$helper_plist" "MachServices:${HELPER_ID}" "true" "privileged helper Mach service"
    expect_text "Sources/KeyPathCore/KeyPathConstants.swift" "public static let helperID = \"$HELPER_ID\"" "privileged helper ID constant is pinned"

    expect_plist_value "$kanata_plist" "Label" "$KANATA_DAEMON_ID" "Kanata daemon label"
    expect_plist_value "$kanata_plist" "BundleProgram" "Contents/Library/KeyPath/kanata-launcher" "Kanata daemon BundleProgram"
    expect_plist_value "$kanata_plist" "ProgramArguments:0" "Contents/Library/KeyPath/kanata-launcher" "Kanata daemon argv[0]"
    expect_plist_value "$kanata_plist" "AssociatedBundleIdentifiers:0" "com.keypath.KeyPath" "Kanata daemon associated bundle ID"
    expect_text "Scripts/build-and-sign.sh" "--identifier \"$HELPER_ID\"" "release signing pins helper identifier"
}

verify_app_contract() {
    local app=$APP_PATH
    if [[ ! -d "$app" ]]; then
        fail "KeyPath.app artifact missing at $app"
        return
    fi

    local kanata_engine="$app/Contents/Library/KeyPath/Kanata Engine.app"
    local kanata_binary="$kanata_engine/Contents/MacOS/kanata"
    local kanata_info="$kanata_engine/Contents/Info.plist"
    local kanata_plist="$app/Contents/Library/LaunchDaemons/com.keypath.kanata.plist"
    local launcher="$app/Contents/Library/KeyPath/kanata-launcher"
    local helper="$app/Contents/Library/HelperTools/KeyPathHelper"
    local helper_plist="$app/Contents/Library/LaunchDaemons/com.keypath.helper.plist"

    expect_file "$kanata_binary" "Kanata Engine binary"
    expect_file "$launcher" "Kanata daemon shell"
    expect_file "$helper" "privileged helper"
    expect_file "$kanata_plist" "Kanata daemon plist"
    expect_file "$helper_plist" "privileged helper plist"

    expect_plist_value "$kanata_info" "CFBundleIdentifier" "$KANATA_ENGINE_ID" "signed Kanata Engine bundle ID"
    expect_plist_value "$kanata_plist" "Label" "$KANATA_DAEMON_ID" "signed Kanata daemon label"
    expect_plist_value "$kanata_plist" "BundleProgram" "Contents/Library/KeyPath/kanata-launcher" "signed Kanata daemon BundleProgram"
    expect_plist_value "$kanata_plist" "AssociatedBundleIdentifiers:0" "com.keypath.KeyPath" "signed Kanata daemon associated bundle ID"
    expect_plist_value "$helper_plist" "Label" "$HELPER_ID" "signed helper launchd label"
    expect_plist_value "$helper_plist" "BundleProgram" "Contents/Library/HelperTools/KeyPathHelper" "signed helper BundleProgram"

    expect_codesign_identity "$kanata_engine" "$KANATA_ENGINE_ID" "$KANATA_ENGINE_REQ" "Kanata Engine.app"
    expect_codesign_identity "$kanata_binary" "$KANATA_ENGINE_ID" "$KANATA_ENGINE_REQ" "Kanata Engine binary"
    expect_codesign_identity "$helper" "$HELPER_ID" "$HELPER_REQ" "KeyPathHelper"
    expect_codesign_identity "$launcher" "$KANATA_LAUNCHER_ID" "$KANATA_LAUNCHER_REQ" "kanata-launcher"
}

if [[ "$MODE" == "source" ]]; then
    verify_source_contract
else
    verify_app_contract
fi

if (( failures > 0 )); then
    echo "[identity-contract] ${failures} failure(s)" >&2
    exit 1
fi

echo "[identity-contract] all checks passed"
