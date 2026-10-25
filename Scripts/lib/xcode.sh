#!/bin/bash

# Canonical local Xcode selection for KeyPath build, test, deploy, and release scripts.
# Uses the Xcode that `xcode-select` points at. Set KEYPATH_DEV_XCODE_DEVELOPER_DIR to
# build with a different Xcode without changing the machine-wide selection.

keypath_xcode_version() {
    local developer_dir="$1"
    if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
        return 1
    fi
    "$developer_dir/usr/bin/xcodebuild" -version 2>/dev/null | sed -n 's/^Xcode //p' | head -n 1
}

keypath_xcode_build() {
    local developer_dir="$1"
    if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
        return 1
    fi
    "$developer_dir/usr/bin/xcodebuild" -version 2>/dev/null | sed -n 's/^Build version //p' | head -n 1
}

# True when the developer directory or version names a beta. Build numbers are not
# used: released Xcodes also end in a lowercase letter (15.4 is 15F31d, 16.0 is 16A242d).
keypath_xcode_looks_beta() {
    local developer_dir="$1" version="${2:-}"
    [[ "$developer_dir" == *[Bb]eta* || "$version" == *[Bb]eta* ]]
}

keypath_use_selected_xcode() {
    if [[ -n "${KEYPATH_DEV_XCODE_DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR="$KEYPATH_DEV_XCODE_DEVELOPER_DIR"
    else
        local selected
        selected="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
        if [[ -z "$selected" ]]; then
            echo "❌ No Xcode is selected. Run: sudo xcode-select -s /Applications/Xcode.app" >&2
            return 1
        fi
        export DEVELOPER_DIR="$selected"
    fi

    # Command Line Tools have no xcodebuild and no Metal compiler; KeyPath needs a full Xcode.
    if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        echo "❌ $DEVELOPER_DIR is not a full Xcode developer directory." >&2
        echo "   Select an Xcode with xcode-select, or set KEYPATH_DEV_XCODE_DEVELOPER_DIR." >&2
        return 1
    fi
    echo "🛠  Using Xcode $(keypath_xcode_version "$DEVELOPER_DIR" || echo unknown) at $DEVELOPER_DIR" >&2

    # Rust invokes the system compiler through `cc`; without an explicit SDK it
    # can resolve Command Line Tools even when DEVELOPER_DIR points at Xcode.
    # Keep every compiler on the same selected Xcode SDK.
    export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
}
