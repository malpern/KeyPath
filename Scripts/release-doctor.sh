#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)
source "$SCRIPT_DIR/lib/xcode.sh"
source "$SCRIPT_DIR/lib/signing.sh"
source "$SCRIPT_DIR/lib/sparkle.sh"
source "$SCRIPT_DIR/lib/release-cleanliness.sh"
export KEYPATH_PROJECT_DIR="$PROJECT_DIR"
keypath_use_stable_xcode

MODE="release-candidate"
STRICT=0

usage() {
    cat <<'EOF'
Usage: Scripts/release-doctor.sh [--release-candidate|--ship] [--strict]

Preflight the local machine and repository before a signed/notarized KeyPath
build. This script is read-only: it does not build, sign, notarize, publish,
restart services, or modify git state.

Modes:
  --release-candidate  Check the default post-merge manual-test path.
  --ship               Also check Sparkle and website publishing prerequisites.

Options:
  --strict             Treat warnings as failures.
  -h, --help           Show this help.

Environment checked:
  CODESIGN_IDENTITY    Developer ID Application identity override.
  NOTARY_PROFILE       notarytool keychain profile override.
  KP_NOTARY_KEYCHAIN   Optional notarytool keychain override.
  KP_NOTARY_KEY_PATH / KP_NOTARY_KEY_ID / KP_NOTARY_ISSUER
                       App Store Connect API key for notarytool (defaults to
                       the AuthKey under ~/.appstoreconnect when present).
  SKIP_SPARKLE         If 1, skip Sparkle checks.
  SKIP_WEBSITE         If 1, skip gh-pages website checks.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release-candidate)
            MODE="release-candidate"
            ;;
        --ship)
            MODE="ship"
            ;;
        --strict)
            STRICT=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

failures=0
warnings=0

print_section() {
    echo
    echo "== $1 =="
}

pass() {
    echo "✅ $1"
}

warn() {
    warnings=$((warnings + 1))
    echo "⚠️  $1"
}

fail() {
    failures=$((failures + 1))
    echo "❌ $1"
}

check_command() {
    local command_name=$1
    if command -v "$command_name" >/dev/null 2>&1; then
        pass "$command_name available ($(command -v "$command_name"))"
    else
        fail "$command_name is missing"
    fi
}

check_optional_command() {
    local command_name=$1
    if command -v "$command_name" >/dev/null 2>&1; then
        pass "$command_name available ($(command -v "$command_name"))"
    else
        warn "$command_name is missing"
    fi
}

notarytool() {
    xcrun notarytool "$@"
}

find_worktree_for_branch() {
    local branch_name=$1
    git worktree list --porcelain | awk -v target="refs/heads/${branch_name}" '
        /^worktree / { path=substr($0, 10) }
        /^branch / {
            if ($2 == target) {
                print path
                exit
            }
        }
    '
}

cd "$PROJECT_DIR"

print_section "Release Doctor"
echo "Mode: $MODE"

print_section "Required Tools"
check_command swift
check_command xcrun
check_command codesign
check_command security
check_command ditto
check_command git
if [[ "$MODE" == "ship" ]]; then
    check_command gh
else
    check_optional_command gh
fi
check_command nc

print_section "Disk Space"
available_kb=$(df -Pk "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "$available_kb" ]]; then
    available_gb=$((available_kb / 1024 / 1024))
    if (( available_gb < 5 )); then
        warn "Low disk space: ${available_gb}GB available on project volume; SwiftPM builds and notarization artifacts can be large"
    else
        pass "Project volume has ${available_gb}GB available"
    fi
else
    warn "Could not determine available disk space for $PROJECT_DIR"
fi

print_section "Git State"
branch=$(git branch --show-current || true)
if [[ -n "$branch" ]]; then
    pass "Current branch: $branch"
else
    warn "Detached HEAD"
fi

if kp_release_require_clean_source "$PROJECT_DIR"; then
    pass "Repository, lockfiles, and recursive submodules match HEAD"
else
    fail "Release source is not reproducible"
fi

master_worktree=$(find_worktree_for_branch master)
if [[ -n "$master_worktree" ]]; then
    if [[ "$master_worktree" != "$PROJECT_DIR" ]]; then
        warn "master is checked out in another worktree: $master_worktree"
        echo "   Merge PRs through GitHub or from outside this repo, then fetch/prune before deploying."
    else
        pass "This worktree owns master"
    fi
else
    warn "No local worktree currently owns master"
fi

print_section "Signing and Notarization"
signing_identity="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
notary_profile="${NOTARY_PROFILE:-KeyPath-Profile}"

if security find-identity -v -p codesigning 2>/dev/null | grep -F "$signing_identity" >/dev/null; then
    pass "Codesign identity found: $signing_identity"
else
    fail "Codesign identity not found: $signing_identity"
    echo "   Set CODESIGN_IDENTITY or install the Developer ID Application certificate."
fi

# Validate the same auth path build-and-sign.sh will use. The API key is
# preferred because keychain profiles become unreadable if the session locks
# mid-build (data-protection keychain).
kp_notary_default_auth_from_environment
if ! kp_notary_resolve_auth "$notary_profile"; then
    fail "notarytool auth configuration is invalid (KP_NOTARY_KEY_* incomplete or key file missing)"
elif notarytool history "${KP_NOTARY_AUTH_ARGS[@]}" --output-format json >/dev/null 2>&1; then
    if [[ -n "${KP_NOTARY_KEY_PATH:-}" ]]; then
        pass "notarytool App Store Connect API key validated: ${KP_NOTARY_KEY_ID:-?} (no keychain dependency)"
    else
        pass "notarytool profile validated: $notary_profile"
        echo "   Note: keychain-profile auth fails if the session locks mid-build; prefer an App Store Connect API key (KP_NOTARY_KEY_PATH)."
    fi
else
    if [[ -n "${KP_NOTARY_KEY_PATH:-}" ]]; then
        fail "notarytool App Store Connect API key failed validation: $KP_NOTARY_KEY_PATH"
    else
        fail "notarytool profile failed validation: $notary_profile"
        echo "   Set NOTARY_PROFILE or run: xcrun notarytool store-credentials"
    fi
fi

print_section "Identity Contract"
if "$PROJECT_DIR/Scripts/verify-identity-contract.sh" --source; then
    pass "Installer identity-stability source contract passed"
else
    fail "Installer identity-stability source contract failed"
fi

print_section "Release Signing Contract"
if "$PROJECT_DIR/Scripts/verify-release-signing-contract.sh" --source; then
    pass "Release signing source contract passed"
else
    fail "Release signing source contract failed"
fi

print_section "Release Artifacts"
effective_skip_sparkle="${SKIP_SPARKLE:-}"
effective_skip_website="${SKIP_WEBSITE:-}"
if [[ "$MODE" == "release-candidate" ]]; then
    effective_skip_sparkle="${SKIP_SPARKLE:-1}"
    effective_skip_website="${SKIP_WEBSITE:-1}"
fi

if [[ "$effective_skip_sparkle" == "1" ]]; then
    pass "Sparkle archive checks skipped (SKIP_SPARKLE=1)"
else
    keypath_load_sparkle_private_key || true
    if sign_update_path=$(keypath_resolve_sparkle_tool sign_update); then
        pass "Sparkle sign_update found: $sign_update_path"
    else
        fail "Sparkle sign_update not found; public Sparkle archive signing would fail"
    fi

    if generate_appcast_path=$(keypath_resolve_sparkle_tool generate_appcast); then
        pass "Sparkle generate_appcast found: $generate_appcast_path"
    else
        fail "Sparkle generate_appcast not found; public appcast generation would fail"
    fi

    if generate_keys_path=$(keypath_resolve_sparkle_tool generate_keys); then
        pass "Sparkle generate_keys found: $generate_keys_path"
    else
        fail "Sparkle generate_keys not found; signing identity cannot be verified"
    fi

    if keypath_verify_sparkle_signing_identity "$PROJECT_DIR/Sources/KeyPathApp/Info.plist"; then
        pass "Sparkle signing identity '$KEYPATH_SPARKLE_ACCOUNT' matches SUPublicEDKey"
    else
        fail "Sparkle signing identity '$KEYPATH_SPARKLE_ACCOUNT' does not match SUPublicEDKey"
    fi

    if keypath_verify_sparkle_feed "$PROJECT_DIR/appcast.xml" >/dev/null 2>&1; then
        pass "Committed Sparkle appcast signature verified"
    else
        fail "Committed Sparkle appcast is unsigned or has an invalid signature"
    fi

    if command -v create-dmg >/dev/null 2>&1; then
        pass "create-dmg available"
    else
        warn "create-dmg missing; build-and-sign.sh will create a plain fallback DMG"
    fi
fi

if [[ "$effective_skip_website" == "1" ]]; then
    pass "Website publish checks skipped (SKIP_WEBSITE=1)"
else
    ghpages_dir=$(find_worktree_for_branch gh-pages)
    if [[ -n "$ghpages_dir" && ( -d "$ghpages_dir/.git" || -f "$ghpages_dir/.git" ) ]]; then
        pass "gh-pages worktree found: $ghpages_dir"
        if git -C "$ghpages_dir" diff --quiet && git -C "$ghpages_dir" diff --cached --quiet; then
            pass "gh-pages worktree has no tracked changes"
        else
            fail "gh-pages worktree has uncommitted tracked changes"
        fi
        if [[ -n "$(git -C "$ghpages_dir" status --porcelain --untracked-files=normal)" ]]; then
            warn "gh-pages worktree has untracked files"
        fi
    elif git show-ref --verify --quiet refs/heads/gh-pages || git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
        pass "gh-pages branch found; release.sh can create a temporary worktree"
    else
        fail "gh-pages branch not found; website download publishing would fail"
    fi
fi

print_section "Installed Runtime"
if pgrep -x KeyPath >/dev/null; then
    pass "KeyPath is currently running"
else
    warn "KeyPath is not currently running"
fi

if launchctl print system/com.keypath.kanata >/dev/null 2>&1; then
    pass "Kanata launchd job is registered"
else
    warn "Kanata launchd job is not registered"
fi

if nc -z -w 1 127.0.0.1 37001 >/dev/null 2>&1; then
    pass "Kanata TCP endpoint is responding on 127.0.0.1:37001"
else
    warn "Kanata TCP endpoint is not responding on 127.0.0.1:37001"
fi

print_section "Background Watchers"
if pgrep -fl 'poltergeist' >/dev/null 2>&1; then
    warn "Poltergeist is running; stop it before release builds to avoid SwiftPM lock contention"
    pgrep -fl 'poltergeist' || true
else
    pass "Poltergeist is not running"
fi

print_section "Summary"
if (( failures > 0 )); then
    echo "❌ release-doctor found $failures failure(s) and $warnings warning(s)."
    exit 1
fi

if (( STRICT == 1 && warnings > 0 )); then
    echo "❌ release-doctor found $warnings warning(s) in --strict mode."
    exit 1
fi

echo "✅ release-doctor passed with $warnings warning(s)."
