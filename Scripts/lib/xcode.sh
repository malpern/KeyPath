#!/bin/bash

# Canonical local Xcode selection for KeyPath build, test, deploy, and release scripts.
# Set KEYPATH_DEV_XCODE_DEVELOPER_DIR only when intentionally validating another toolchain.

KEYPATH_STABLE_XCODE_VERSION="${KEYPATH_STABLE_XCODE_VERSION:-26.6}"
KEYPATH_STABLE_XCODE_DEVELOPER_DIR="${KEYPATH_STABLE_XCODE_DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"

keypath_xcode_version() {
    local developer_dir="$1"
    if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
        return 1
    fi
    "$developer_dir/usr/bin/xcodebuild" -version 2>/dev/null | sed -n 's/^Xcode //p' | head -n 1
}

keypath_use_stable_xcode() {
    if [[ -n "${KEYPATH_DEV_XCODE_DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR="$KEYPATH_DEV_XCODE_DEVELOPER_DIR"
    else
        local candidate
        local candidate_version
        local stable_developer_dir=""
        for candidate in \
            "$KEYPATH_STABLE_XCODE_DEVELOPER_DIR" \
            /Applications/Xcode.app/Contents/Developer \
            /Applications/Xcode-*.app/Contents/Developer
        do
            candidate_version="$(keypath_xcode_version "$candidate" || true)"
            if [[ "$candidate_version" == "$KEYPATH_STABLE_XCODE_VERSION" ]]; then
                stable_developer_dir="$candidate"
                break
            fi
        done

        if [[ -z "$stable_developer_dir" ]]; then
            echo "❌ Xcode $KEYPATH_STABLE_XCODE_VERSION is not installed under /Applications." >&2
            echo "   Install it or set KEYPATH_DEV_XCODE_DEVELOPER_DIR for an intentional override." >&2
            return 1
        fi
        export DEVELOPER_DIR="$stable_developer_dir"
    fi

    if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        echo "❌ Invalid Xcode developer directory: $DEVELOPER_DIR" >&2
        return 1
    fi
}
