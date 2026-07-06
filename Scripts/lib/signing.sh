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

kp_notary_uses_api_key() {
    [ -n "${KP_NOTARY_KEY:-}" ] || [ -n "${KP_NOTARY_KEY_ID:-}" ] || [ -n "${KP_NOTARY_ISSUER:-}" ]
}

kp_notary_validate_api_key_env() {
    local missing=()
    [ -n "${KP_NOTARY_KEY:-}" ] || missing+=("KP_NOTARY_KEY")
    [ -n "${KP_NOTARY_KEY_ID:-}" ] || missing+=("KP_NOTARY_KEY_ID")
    [ -n "${KP_NOTARY_ISSUER:-}" ] || missing+=("KP_NOTARY_ISSUER")

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "❌ ERROR: incomplete App Store Connect notarization credentials." >&2
        echo "   Missing: ${missing[*]}" >&2
        echo "   Set all of KP_NOTARY_KEY, KP_NOTARY_KEY_ID, and KP_NOTARY_ISSUER, or unset them to use NOTARY_PROFILE." >&2
        return 1
    fi

    if [ ! -f "$KP_NOTARY_KEY" ]; then
        echo "❌ ERROR: KP_NOTARY_KEY does not exist: $KP_NOTARY_KEY" >&2
        return 1
    fi
}

kp_notary_args() {
    local profile=$1
    if kp_notary_uses_api_key; then
        kp_notary_validate_api_key_env || return 1
        printf '%s\n' --key "$KP_NOTARY_KEY" --key-id "$KP_NOTARY_KEY_ID" --issuer "$KP_NOTARY_ISSUER"
    else
        printf '%s\n' --keychain-profile "$profile"
        if [ -n "${KP_NOTARY_KEYCHAIN:-}" ]; then
            printf '%s\n' --keychain "$KP_NOTARY_KEYCHAIN"
        fi
    fi
}

kp_notarize_zip() {
    local zip_path=$1
    local profile=$2
    shift 2
    local notary_args=()
    if kp_notary_uses_api_key; then
        kp_notary_validate_api_key_env || return 1
    fi
    while IFS= read -r arg; do
        notary_args+=("$arg")
    done < <(kp_notary_args "$profile")

    if [ "$KP_SIGN_DRY_RUN" = "1" ]; then
        echo "[DRY RUN] $KP_NOTARY_CMD submit $zip_path ${notary_args[*]} --wait $*"
        return 0
    fi
    # Use word-splitting for multi-word command (xcrun notarytool)
    $KP_NOTARY_CMD submit "$zip_path" "${notary_args[@]}" --wait "$@"
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
