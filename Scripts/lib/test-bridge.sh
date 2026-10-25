#!/usr/bin/env bash
# Configuration tests must exercise parsed admission, never the Xcode host's
# nonexistent app bundle. Keep explicit fixtures explicit (including failures).
keypath_prepare_test_bridge() {
    local root="$1"
    if [[ -z "${KEYPATH_SESSION_TEST_BRIDGE_PATH:-}" ]]; then
        (cd "$root" && "$root/Scripts/build-kanata-host-bridge.sh") || return $?
        export KEYPATH_SESSION_TEST_BRIDGE_PATH="$root/build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib"
    fi
    if [[ ! -f "$KEYPATH_SESSION_TEST_BRIDGE_PATH" ]]; then
        echo "Missing test bridge: $KEYPATH_SESSION_TEST_BRIDGE_PATH" >&2
        return 1
    fi
}
