#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
MDM_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-managed-probe-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

write_tool() {
    local name=$1 body=$2
    printf '#!/bin/bash\n%s\n' "$body" > "$TMP/$name"
    chmod +x "$TMP/$name"
}

write_status() {
    write_tool keypath-cli "cat <<JSON
$1
JSON"
}

write_status '{"apiVersion":1,"data":{"isOperational":true,"keyPathAccessibility":true,"runtimeKeyAccess":true,"kanataBinaryInstalled":true,"kanataRunning":true,"hasConflicts":false}}'
write_tool tcp-probe 'echo "{\"CurrentLayerName\":{\"name\":\"base\"}}"'
write_tool sfltool 'echo "background items available"'

run_probe() {
    KEYPATH_LAB_CLI="$TMP/keypath-cli" \
    KEYPATH_LAB_TCP_PROBE="$TMP/tcp-probe" \
    KEYPATH_LAB_SFLTOOL="$TMP/sfltool" \
        "$MDM_DIR/probe-managed-capabilities" --output "$1"
}

# A ready session runtime passes without any driver, helper, or LaunchDaemon.
run_probe "$TMP/pass" >/dev/null
grep -Fq $'managed_capabilities\tpassed' "$TMP/pass/result.tsv"
test -s "$TMP/pass/service-status.json"
test -s "$TMP/pass/tcp-readiness.json"
test -s "$TMP/pass/background-items.txt"

write_status '{"apiVersion":1,"data":{"isOperational":true,"keyPathAccessibility":false,"runtimeKeyAccess":true,"kanataBinaryInstalled":true,"kanataRunning":true,"hasConflicts":false}}'
if run_probe "$TMP/missing-permission" >"$TMP/missing.stdout" 2>"$TMP/missing.stderr"; then
    echo "expected missing KeyPath Accessibility to fail" >&2
    exit 1
fi
grep -Fq 'managed capabilities missing: keyPathAccessibility' "$TMP/missing.stderr"

# The unwrapped payload shape is accepted too; a stopped runtime fails.
write_status '{"isOperational":false,"keyPathAccessibility":true,"runtimeKeyAccess":true,"kanataBinaryInstalled":true,"kanataRunning":false,"hasConflicts":false}'
if run_probe "$TMP/stopped-runtime" >"$TMP/stopped.stdout" 2>"$TMP/stopped.stderr"; then
    echo "expected a stopped session runtime to fail" >&2
    exit 1
fi
grep -Fq 'managed capabilities missing: isOperational, kanataRunning' "$TMP/stopped.stderr"

write_status '{"apiVersion":1,"data":{"isOperational":true,"keyPathAccessibility":true,"runtimeKeyAccess":true,"kanataBinaryInstalled":true,"kanataRunning":true,"hasConflicts":true}}'
if run_probe "$TMP/conflict" >"$TMP/conflict.stdout" 2>"$TMP/conflict.stderr"; then
    echo "expected a conflicting remapper to fail" >&2
    exit 1
fi
grep -Fq 'conflicting remapper detected' "$TMP/conflict.stderr"

echo "managed-capability-probe-tests: passed"
