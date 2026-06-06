#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)

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

resolve_sign_update() {
    if [[ -n "${KP_SPARKLE_SIGN_CMD:-}" && -x "${KP_SPARKLE_SIGN_CMD:-}" ]]; then
        echo "$KP_SPARKLE_SIGN_CMD"
        return 0
    fi

    if command -v sign_update >/dev/null 2>&1; then
        command -v sign_update
        return 0
    fi

    local cask_version=""
    cask_version="$(brew list --cask --versions sparkle 2>/dev/null | awk '{print $2}')" || cask_version=""
    local cask_root candidate
    for cask_root in /opt/homebrew/Caskroom/sparkle /usr/local/Caskroom/sparkle; do
        if [[ -n "$cask_version" && -x "$cask_root/$cask_version/bin/sign_update" ]]; then
            echo "$cask_root/$cask_version/bin/sign_update"
            return 0
        fi
        candidate="$(ls -1dt "$cask_root"/*/bin/sign_update 2>/dev/null | head -n1 || true)"
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
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

print_section "Git State"
branch=$(git branch --show-current || true)
if [[ -n "$branch" ]]; then
    pass "Current branch: $branch"
else
    warn "Detached HEAD"
fi

if git diff --quiet && git diff --cached --quiet; then
    pass "Working tree has no tracked changes"
else
    warn "Working tree has tracked changes; release builds should normally run from clean master"
fi

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    warn "Working tree has untracked files"
fi

if git worktree list --porcelain | grep -q '^branch refs/heads/master$'; then
    master_worktree=$(git worktree list --porcelain | awk '
        /^worktree / { path=$2 }
        /^branch refs\/heads\/master$/ { print path; exit }
    ')
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

notary_args=(history --keychain-profile "$notary_profile" --output-format json)
if [[ -n "${KP_NOTARY_KEYCHAIN:-}" ]]; then
    notary_args+=(--keychain "$KP_NOTARY_KEYCHAIN")
fi

if notarytool "${notary_args[@]}" >/dev/null 2>&1; then
    pass "notarytool profile validated: $notary_profile"
else
    fail "notarytool profile failed validation: $notary_profile"
    echo "   Set NOTARY_PROFILE or run: xcrun notarytool store-credentials"
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
    if sign_update_path=$(resolve_sign_update); then
        pass "Sparkle sign_update found: $sign_update_path"
    elif [[ "${ALLOW_UNSIGNED_SPARKLE:-0}" == "1" ]]; then
        warn "Sparkle sign_update missing, but ALLOW_UNSIGNED_SPARKLE=1"
    else
        fail "Sparkle sign_update not found; public Sparkle archive signing would fail"
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
    ghpages_dir="$PROJECT_DIR/.worktrees/gh-pages"
    if [[ -d "$ghpages_dir/.git" || -f "$ghpages_dir/.git" ]]; then
        pass "gh-pages worktree found: $ghpages_dir"
        if git -C "$ghpages_dir" diff --quiet && git -C "$ghpages_dir" diff --cached --quiet; then
            pass "gh-pages worktree has no tracked changes"
        else
            fail "gh-pages worktree has uncommitted tracked changes"
        fi
        if [[ -n "$(git -C "$ghpages_dir" status --porcelain --untracked-files=normal)" ]]; then
            warn "gh-pages worktree has untracked files"
        fi
    else
        fail "gh-pages worktree missing at $ghpages_dir"
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

if nc -vz -w 1 127.0.0.1 37001 >/dev/null 2>&1; then
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
