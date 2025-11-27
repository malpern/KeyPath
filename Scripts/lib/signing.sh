#!/bin/bash

# Lightweight signing/notarization helpers.
# - Wraps the external tools so tests can swap in stubs.
# - Honors KP_SIGN_DRY_RUN=1 to echo instead of executing.

KP_SIGN_CMD=${KP_SIGN_CMD:-codesign}
KP_NOTARY_CMD=${KP_NOTARY_CMD:-xcrun notarytool}
KP_STAPLER_CMD=${KP_STAPLER_CMD:-xcrun stapler}
KP_SPCTL_CMD=${KP_SPCTL_CMD:-spctl}
KP_VERIFY_CMD=${KP_VERIFY_CMD:-codesign}
KP_SIGN_DRY_RUN=${KP_SIGN_DRY_RUN:-0}

kp_run() {
    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $*"
        return 0
    fi
    "$@"
}

kp_sign() {
    local target=$1
    shift
    kp_run "$KP_SIGN_CMD" "$@" "$target"
}

kp_verify_signature() {
    local target=$1
    shift
    kp_run "$KP_VERIFY_CMD" -dvvv "$target" "$@"
}

kp_notarize_zip() {
    local zip_path=$1
    local profile=$2
    shift 2
    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $KP_NOTARY_CMD submit $zip_path --keychain-profile $profile --wait $*"
        return 0
    fi
    # Use word-splitting for multi-word command (xcrun notarytool)
    $KP_NOTARY_CMD submit "$zip_path" --keychain-profile "$profile" --wait "$@"
}

kp_staple() {
    local target=$1
    shift
    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $KP_STAPLER_CMD staple $target $*"
        return 0
    fi
    # Use word-splitting for multi-word command (xcrun stapler)
    $KP_STAPLER_CMD staple "$target" "$@"
}

kp_spctl_assess() {
    local target=$1
    shift
    kp_run "$KP_SPCTL_CMD" -a -vvv "$target" "$@"
}
