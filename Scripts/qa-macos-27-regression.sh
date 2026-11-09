#!/bin/bash
set -euo pipefail

APP_PATH=${KEYPATH_MACOS27_QA_APP_PATH:-/Applications/KeyPath.app}
CLI="$APP_PATH/Contents/MacOS/keypath-cli"
OUTPUT_ROOT=${1:-"${TMPDIR:-/tmp}/keypath-macos27-qa-$(date -u +%Y%m%dT%H%M%SZ)"}

die() {
    echo "qa-macos-27-regression: $*" >&2
    exit 1
}

product_version=$(sw_vers -productVersion)
product_major=${product_version%%.*}
if [[ $product_major != 27 && ${KEYPATH_MACOS27_QA_ALLOW_OTHER_OS:-0} != 1 ]]; then
    die "requires macOS 27 (found $product_version)"
fi
[[ -d $APP_PATH ]] || die "installed app not found: $APP_PATH"
[[ -x $CLI ]] || die "installed CLI not found: $CLI"

mkdir -p "$OUTPUT_ROOT"
sw_vers > "$OUTPUT_ROOT/sw-vers.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUTPUT_ROOT/captured-at.txt"

"$CLI" system inspect --json > "$OUTPUT_ROOT/system-inspect.json"
"$CLI" status --json > "$OUTPUT_ROOT/runtime-status.json" 2>&1 || true

codesign --verify --deep --strict --verbose=2 "$APP_PATH" > "$OUTPUT_ROOT/codesign.txt" 2>&1
if [[ ${KEYPATH_MACOS27_QA_REQUIRE_DISTRIBUTION_TRUST:-1} == 1 ]]; then
    spctl --assess --type execute --verbose=2 "$APP_PATH" > "$OUTPUT_ROOT/gatekeeper.txt" 2>&1
    xcrun stapler validate "$APP_PATH" > "$OUTPUT_ROOT/stapler.txt" 2>&1
else
    echo "skipped: KEYPATH_MACOS27_QA_REQUIRE_DISTRIBUTION_TRUST=0" > "$OUTPUT_ROOT/gatekeeper.txt"
    echo "skipped: KEYPATH_MACOS27_QA_REQUIRE_DISTRIBUTION_TRUST=0" > "$OUTPUT_ROOT/stapler.txt"
fi

pgrep -fl "$APP_PATH/Contents/MacOS/KeyPath" > "$OUTPUT_ROOT/keypath-process.txt" || true
nc -vz 127.0.0.1 37001 > "$OUTPUT_ROOT/tcp-readiness.txt" 2>&1

mkdir -p "$OUTPUT_ROOT/logs"
cp "$HOME/Library/Logs/KeyPath/keypath-debug.log" "$OUTPUT_ROOT/logs/" 2>/dev/null || true

cat > "$OUTPUT_ROOT/operator-checklist.md" <<'EOF'
# macOS 27 operator checkpoints

- [ ] In a disposable or clean account, capture the setup summary before granting permissions.
- [ ] Grant and revoke Accessibility; confirm KeyPath reports the current state and recovery action.
- [ ] With only Device Control and Data Access granted, confirm remapping works and no Input Monitoring prompt or row appears.
- [ ] Exercise Background App Activity/Login Items approval and distinguish pending approval from failure.
- [ ] Confirm the VirtualHID Driver Extension approval opens the correct macOS 27 System Settings surface.
- [ ] Type through Kanata and confirm the live overlay renders physical key down/up state correctly.
- [ ] Restart the guest and rerun this capture to verify helper, daemon, and permission persistence.

Do not copy TCC databases, credentials, Apple IDs, or private keys into this artifact directory.
EOF

echo "macOS 27 regression evidence: $OUTPUT_ROOT"
