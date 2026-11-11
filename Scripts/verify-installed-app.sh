#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/KeyPath.app}"
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
VERIFY_PYTHON="${KEYPATH_VERIFY_PYTHON:-python3}"
RUNTIME_TIMEOUT_SECONDS="${KEYPATH_RUNTIME_TIMEOUT_SECONDS:-${KEYPATH_TCP_TIMEOUT_SECONDS:-20}}"
REQUIRE_NOTARIZED="${REQUIRE_NOTARIZED:-1}"
REQUIRE_STAPLED="${REQUIRE_STAPLED:-1}"
CHECK_RUNTIME="${CHECK_RUNTIME:-1}"

print_section() {
    echo
    echo "== $1 =="
}

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App not found: $APP_PATH" >&2
    exit 1
fi

for resource_bundle in \
    KeyPath_KeyPath.bundle \
    KeyPath_KeyPathAppKit.bundle \
    KeyPath_KeyPathInstallationWizard.bundle; do
    packaged_bundle="$APP_PATH/Contents/Resources/$resource_bundle"
    if [[ ! -d "$packaged_bundle" ]]; then
        echo "❌ Packaged SwiftPM resource bundle is missing: $packaged_bundle" >&2
        exit 1
    fi
done
metal_library="$APP_PATH/Contents/Resources/KeyPath_KeyPathAppKit.bundle/default.metallib"
if [[ ! -f "$metal_library" || ! -s "$metal_library" ]]; then
    metal_library="$APP_PATH/Contents/Resources/KeyPath_KeyPathAppKit.bundle/Contents/Resources/default.metallib"
fi
if [[ ! -f "$metal_library" || ! -s "$metal_library" ]]; then
    echo "❌ Packaged Metal library is missing or empty in the KeyPathAppKit resource bundle" >&2
    exit 1
fi

bash "$SCRIPT_DIR/verify-apple-silicon.sh" "$APP_PATH"

CLI_PATH="$APP_PATH/Contents/MacOS/keypath-cli"
if [[ ! -x "$CLI_PATH" ]]; then
    echo "❌ Bundled CLI is missing or not executable: $CLI_PATH" >&2
    exit 1
fi
SPARKLE_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
if [[ ! -f "$SPARKLE_PATH" ]]; then
    echo "❌ Sparkle.framework binary is missing: $SPARKLE_PATH" >&2
    exit 1
fi
for executable in "$APP_PATH/Contents/MacOS/KeyPath" "$CLI_PATH"; do
    if ! otool -l "$executable" | grep -q "@executable_path/../Frameworks"; then
        echo "❌ $(basename "$executable") is missing @executable_path/../Frameworks rpath" >&2
        echo "   Without this, dyld cannot load the embedded Sparkle.framework at launch." >&2
        exit 1
    fi
done
cli_codesign_output="$(codesign -dv "$CLI_PATH" 2>&1)"
if ! grep -q '^Identifier=com\.keypath\.KeyPath\.CLI$' <<<"$cli_codesign_output"; then
    echo "❌ Bundled CLI is not signed with identifier com.keypath.KeyPath.CLI" >&2
    echo "   Release CLI identity must remain stable across app replacements." >&2
    exit 1
fi

print_section "Trust Policy"
codesign --verify --strict --verbose=2 "$APP_PATH"
if [[ "$REQUIRE_NOTARIZED" == "1" ]]; then
    spctl -a -vvv -t install "$APP_PATH"
else
    echo "⏭️  Skipping Gatekeeper assessment (REQUIRE_NOTARIZED=0)"
fi

if [[ "$REQUIRE_STAPLED" == "1" ]]; then
    xcrun stapler validate "$APP_PATH"
else
    echo "⏭️  Skipping stapler validation (REQUIRE_STAPLED=0)"
fi

print_section "App Intents Metadata"
# Shortcuts and Siri. Runs after the trust checks, so a pre-1.0.2 install
# still gets its trust report. The expected intents come from this checkout's
# Sources/KeyPathAppKit, so verify a build made from the same tree. Release builds generate it in
# build-and-sign.sh; quick-deploy and ui-deploy do not, so by default it is
# required only together with notarization.
if [[ "${REQUIRE_APP_INTENTS_METADATA:-$REQUIRE_NOTARIZED}" == "1" ]]; then
    actions_data="$APP_PATH/Contents/Resources/Metadata.appintents/extract.actionsdata"
    if [[ ! -s "$actions_data" ]]; then
        echo "❌ App Intents metadata is missing: $actions_data" >&2
        echo "   Shortcuts and Siri cannot see KeyPath's intents without it." >&2
        exit 1
    fi
    if ! command -v "$VERIFY_PYTHON" >/dev/null 2>&1; then
        echo "❌ Python 3 is required to check App Intents metadata; set KEYPATH_VERIFY_PYTHON" >&2
        exit 1
    fi
    if ! "$VERIFY_PYTHON" "$SCRIPT_DIR/check-app-intents-metadata.py" \
        "$actions_data" "$SCRIPT_DIR/../Sources/KeyPathAppKit"; then
        echo "❌ App Intents metadata does not match this checkout's Sources/KeyPathAppKit" >&2
        echo "   If the app was built from another commit, run this script from that tree." >&2
        exit 1
    fi
else
    echo "⏭️  Skipping App Intents metadata check (REQUIRE_APP_INTENTS_METADATA=0)"
fi

if [[ "$CHECK_RUNTIME" != "1" ]]; then
    echo "⏭️  Skipping runtime checks (CHECK_RUNTIME=0)"
    echo "✅ Installed KeyPath passed requested trust checks."
    exit 0
fi

print_section "Bundled CLI"
"$CLI_PATH" --version

print_section "Driverless Session and Engine Socket"
if ! command -v "$VERIFY_PYTHON" >/dev/null 2>&1; then
    echo "❌ Python 3 is required for owned-session verification; set KEYPATH_VERIFY_PYTHON" >&2
    exit 1
fi
"$VERIFY_PYTHON" "$SCRIPT_DIR/verify-session-runtime.py" \
    --app "$APP_PATH" --timeout "$RUNTIME_TIMEOUT_SECONDS"
echo "✅ Installed KeyPath passed requested trust checks and owned-session runtime verification."
