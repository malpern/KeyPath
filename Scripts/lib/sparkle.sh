#!/usr/bin/env bash

# Shared Sparkle tooling for release scripts. This file intentionally keeps the
# private key out of argv and logs: interactive releases use the dedicated
# Keychain account, while unattended callers may pipe KEYPATH_SPARKLE_PRIVATE_KEY
# to Sparkle through stdin.

KEYPATH_SPARKLE_ACCOUNT="${KEYPATH_SPARKLE_ACCOUNT:-keypath}"

keypath_load_sparkle_private_key() {
    if [[ -n "${KEYPATH_SPARKLE_PRIVATE_KEY:-}" ]]; then
        return 0
    fi

    local secrets_file="${KEYPATH_SECRETS_FILE:-$HOME/dotfiles/secrets.env}"
    if ! command -v sops >/dev/null 2>&1 || [[ ! -f "$secrets_file" ]]; then
        return 1
    fi

    local line key value
    while IFS= read -r line; do
        key="${line%%=*}"
        value="${line#*=}"
        if [[ "$key" == "KEYPATH_SPARKLE_PRIVATE_KEY" ]]; then
            KEYPATH_SPARKLE_PRIVATE_KEY="$value"
            return 0
        fi
    done < <(sops -d "$secrets_file" 2>/dev/null)

    return 1
}

keypath_resolve_sparkle_tool() {
    local tool_name=$1
    local override_value=""
    case "$tool_name" in
        generate_appcast) override_value="${KP_SPARKLE_GENERATE_APPCAST_CMD:-}" ;;
        generate_keys) override_value="${KP_SPARKLE_GENERATE_KEYS_CMD:-}" ;;
        sign_update) override_value="${KP_SPARKLE_SIGN_CMD:-}" ;;
        *)
            echo "Unsupported Sparkle tool: $tool_name" >&2
            return 2
            ;;
    esac

    if [[ -n "$override_value" && -x "$override_value" ]]; then
        echo "$override_value"
        return 0
    fi

    local project_dir="${KEYPATH_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)}"
    local artifact_tool="$project_dir/.build/artifacts/sparkle/Sparkle/bin/$tool_name"
    if [[ -x "$artifact_tool" ]]; then
        echo "$artifact_tool"
        return 0
    fi

    if command -v "$tool_name" >/dev/null 2>&1; then
        command -v "$tool_name"
        return 0
    fi

    local cask_version=""
    cask_version="$(brew list --cask --versions sparkle 2>/dev/null | awk '{print $2}')" || cask_version=""
    local cask_root candidate
    for cask_root in /opt/homebrew/Caskroom/sparkle /usr/local/Caskroom/sparkle; do
        if [[ -n "$cask_version" && -x "$cask_root/$cask_version/bin/$tool_name" ]]; then
            echo "$cask_root/$cask_version/bin/$tool_name"
            return 0
        fi
        candidate="$(ls -1dt "$cask_root"/*/bin/"$tool_name" 2>/dev/null | head -n1 || true)"
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

keypath_sparkle_embedded_public_key() {
    local info_plist=$1
    /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$info_plist" 2>/dev/null
}

keypath_sparkle_public_key_from_private_key() {
    printf '%s' "$KEYPATH_SPARKLE_PRIVATE_KEY" | xcrun swift -e '
import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encoded = String(data: input, encoding: .utf8),
      let seed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    exit(2)
}
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
' 2>/dev/null | tr -d '\r\n'
}

keypath_verify_sparkle_signing_identity() {
    local info_plist=$1
    local expected_public_key actual_public_key
    expected_public_key="$(keypath_sparkle_embedded_public_key "$info_plist")" || {
        echo "SUPublicEDKey is missing from $info_plist" >&2
        return 1
    }
    if [[ -n "${KEYPATH_SPARKLE_PRIVATE_KEY:-}" ]]; then
        actual_public_key="$(keypath_sparkle_public_key_from_private_key)" || {
            echo "Could not derive a public key from KEYPATH_SPARKLE_PRIVATE_KEY" >&2
            return 1
        }
    else
        local generate_keys
        generate_keys="$(keypath_resolve_sparkle_tool generate_keys)" || {
            echo "Sparkle generate_keys is unavailable" >&2
            return 1
        }
        actual_public_key="$("$generate_keys" --account "$KEYPATH_SPARKLE_ACCOUNT" -p 2>/dev/null | tr -d '\r\n')" || {
            echo "Could not read Sparkle signing identity '$KEYPATH_SPARKLE_ACCOUNT' from Keychain" >&2
            return 1
        }
    fi

    if [[ -z "$actual_public_key" || "$actual_public_key" != "$expected_public_key" ]]; then
        echo "Sparkle signing identity '$KEYPATH_SPARKLE_ACCOUNT' does not match SUPublicEDKey" >&2
        return 1
    fi
}

keypath_run_generate_appcast() {
    local generate_appcast=$1
    shift
    if [[ -n "${KEYPATH_SPARKLE_PRIVATE_KEY:-}" ]]; then
        printf '%s' "$KEYPATH_SPARKLE_PRIVATE_KEY" | "$generate_appcast" --ed-key-file - "$@"
    else
        "$generate_appcast" --account "$KEYPATH_SPARKLE_ACCOUNT" "$@"
    fi
}

keypath_verify_sparkle_feed() {
    local feed_path=$1
    local sign_update
    sign_update="$(keypath_resolve_sparkle_tool sign_update)" || {
        echo "Sparkle sign_update is unavailable" >&2
        return 1
    }

    if [[ -n "${KEYPATH_SPARKLE_PRIVATE_KEY:-}" ]]; then
        printf '%s' "$KEYPATH_SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - --verify "$feed_path"
    else
        "$sign_update" --account "$KEYPATH_SPARKLE_ACCOUNT" --verify "$feed_path"
    fi
}
