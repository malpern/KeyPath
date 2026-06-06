#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/KeyPath.app}"
KANATA_LABEL="${KANATA_LABEL:-system/com.keypath.kanata}"
TCP_HOST="${KEYPATH_TCP_HOST:-127.0.0.1}"
TCP_PORT="${KEYPATH_TCP_PORT:-37001}"
TCP_TIMEOUT_SECONDS="${KEYPATH_TCP_TIMEOUT_SECONDS:-20}"
REQUIRE_NOTARIZED="${REQUIRE_NOTARIZED:-1}"
REQUIRE_STAPLED="${REQUIRE_STAPLED:-1}"
KANATA_LAUNCHCTL_OUTPUT=$(mktemp -t keypath-kanata-launchctl.XXXXXX)
TCP_PROBE_OUTPUT=$(mktemp -t keypath-tcp-probe.XXXXXX)

cleanup() {
    rm -f "$KANATA_LAUNCHCTL_OUTPUT" "$TCP_PROBE_OUTPUT"
}
trap cleanup EXIT

print_section() {
    echo
    echo "== $1 =="
}

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App not found: $APP_PATH" >&2
    exit 1
fi

print_section "Trust Policy"
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
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

print_section "Processes"
if ! pgrep -x "KeyPath" >/dev/null; then
    echo "❌ KeyPath process is not running" >&2
    exit 1
fi
pgrep -fl 'KeyPath|KeyPathHelper|kanata|kanata-launcher' || true

print_section "Kanata Launchd"
if ! launchctl print "$KANATA_LABEL" >"$KANATA_LAUNCHCTL_OUTPUT" 2>&1; then
    cat "$KANATA_LAUNCHCTL_OUTPUT" >&2
    echo "❌ Kanata launchd job is not registered/running: $KANATA_LABEL" >&2
    exit 1
fi
sed -n '1,140p' "$KANATA_LAUNCHCTL_OUTPUT"

print_section "TCP Readiness"
deadline=$((SECONDS + TCP_TIMEOUT_SECONDS))
while true; do
    if nc -vz -w 1 "$TCP_HOST" "$TCP_PORT" >"$TCP_PROBE_OUTPUT" 2>&1; then
        cat "$TCP_PROBE_OUTPUT"
        echo "✅ Installed KeyPath is signed, notarized, running, and TCP-ready."
        exit 0
    fi

    if (( SECONDS >= deadline )); then
        cat "$TCP_PROBE_OUTPUT" >&2 || true
        echo "❌ TCP did not become ready at ${TCP_HOST}:${TCP_PORT}" >&2
        exit 1
    fi
    sleep 1
done
