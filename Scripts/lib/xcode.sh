#!/bin/bash

# Canonical local Xcode selection for KeyPath build, test, deploy, and release scripts.
# Set KEYPATH_DEV_XCODE_DEVELOPER_DIR only when intentionally validating another toolchain.

KEYPATH_STABLE_XCODE_DEVELOPER_DIR="${KEYPATH_STABLE_XCODE_DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"

keypath_use_stable_xcode() {
    if [[ -n "${KEYPATH_DEV_XCODE_DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR="$KEYPATH_DEV_XCODE_DEVELOPER_DIR"
    elif [[ -d "$KEYPATH_STABLE_XCODE_DEVELOPER_DIR" ]]; then
        export DEVELOPER_DIR="$KEYPATH_STABLE_XCODE_DEVELOPER_DIR"
    else
        echo "❌ Stable Xcode is missing: $KEYPATH_STABLE_XCODE_DEVELOPER_DIR" >&2
        echo "   Install Xcode 26.6 or set KEYPATH_DEV_XCODE_DEVELOPER_DIR for an intentional override." >&2
        return 1
    fi

    if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        echo "❌ Invalid Xcode developer directory: $DEVELOPER_DIR" >&2
        return 1
    fi
}
