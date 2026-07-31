#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
source "$SCRIPT_DIR/lib/signing.sh"
source "$SCRIPT_DIR/lib/release-cleanliness.sh"

VERIFY=1
DOCTOR=1
RESUME=0

usage() {
    cat <<'EOF'
Usage: Scripts/release-candidate.sh [options]

Build a signed/notarized release-candidate app, deploy it to /Applications,
and verify the installed runtime. This is the right path after a PR merge when
you need a real Developer ID + notarized build for local manual testing.

Defaults:
  release-doctor preflight
  SKIP_SNAPSHOTS=1
  SKIP_PEEKABOO=1
  SKIP_SPARKLE=1
  SKIP_WEBSITE=1

Options:
  --with-snapshots    Regenerate help/snapshot images.
  --with-sparkle      Build Sparkle archive/appcast artifacts.
  --with-website      Publish website help content when the release script allows it.
  --with-peekaboo     Allow Peekaboo screenshot generation during snapshot regeneration.
  --no-doctor         Skip Scripts/release-doctor.sh preflight.
  --no-verify         Skip Scripts/verify-installed-app.sh after deploy.
  --resume-notarization
                      Do not rebuild. Finish the notarization recorded in the
                      recovery state, staple dist/KeyPath.app, deploy it
                      unchanged, and verify. Use after a run that stopped at
                      notarization.
  -h, --help          Show this help.

Environment:
  CODESIGN_IDENTITY   Developer ID Application identity override.
  NOTARY_PROFILE      notarytool keychain profile override.
  KP_NOTARY_KEY_PATH / KP_NOTARY_KEY_ID / KP_NOTARY_ISSUER
                      App Store Connect API key for notarytool. Defaults to
                      ~/.appstoreconnect/private_keys/AuthKey_XQ4565NYZ7.p8
                      when that file exists; set KP_NOTARY_AUTH=keychain-profile
                      to force keychain-profile auth instead.
  KP_NOTARY_WAIT_TIMEOUT
                      Maximum Apple processing wait before preserving recovery
                      evidence and stopping (default: 15m).
  KP_NOTARY_STATE_FILE
                      Optional notarization recovery-state file override.
EOF
}

export SKIP_SNAPSHOTS="${SKIP_SNAPSHOTS:-1}"
export SKIP_PEEKABOO="${SKIP_PEEKABOO:-1}"
export SKIP_SPARKLE="${SKIP_SPARKLE:-1}"
export SKIP_WEBSITE="${SKIP_WEBSITE:-1}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-snapshots)
            export SKIP_SNAPSHOTS=0
            ;;
        --with-sparkle)
            export SKIP_SPARKLE=0
            ;;
        --with-website)
            export SKIP_WEBSITE=0
            ;;
        --with-peekaboo)
            export SKIP_PEEKABOO=0
            ;;
        --no-doctor)
            DOCTOR=0
            ;;
        --no-verify)
            VERIFY=0
            ;;
        --resume-notarization)
            RESUME=1
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

cd "$PROJECT_DIR"

if [[ "$RESUME" == "1" ]]; then
    echo "🔁 Resuming release-candidate notarization (no rebuild)"
    "$SCRIPT_DIR/notarize-resume.sh"
    if [[ "$VERIFY" == "1" ]]; then
        "$SCRIPT_DIR/verify-installed-app.sh"
    else
        echo "⏭️  Skipping installed-app verification (--no-verify)"
    fi
    exit 0
fi

if ! kp_release_require_clean_source "$PROJECT_DIR"; then
    echo "❌ Release candidate preflight refused a dirty or mismatched source tree." >&2
    exit 1
fi

echo "🚢 Building release candidate"
echo "   SKIP_SNAPSHOTS=$SKIP_SNAPSHOTS"
echo "   SKIP_PEEKABOO=$SKIP_PEEKABOO"
echo "   SKIP_SPARKLE=$SKIP_SPARKLE"
echo "   SKIP_WEBSITE=$SKIP_WEBSITE"

if [[ "$DOCTOR" == "1" && "${SKIP_RELEASE_DOCTOR:-0}" != "1" ]]; then
    "$SCRIPT_DIR/release-doctor.sh" --release-candidate
else
    echo "⏭️  Skipping release preflight (--no-doctor or SKIP_RELEASE_DOCTOR=1)"
fi

build_status=0
"$SCRIPT_DIR/build-and-sign.sh" || build_status=$?
if [[ "$build_status" -ne 0 ]]; then
    echo "" >&2
    echo "❌ Release candidate failed (build-and-sign exit $build_status)." >&2
    state_file="${KP_NOTARY_STATE_FILE:-dist/KeyPath.notary-submission.json}"
    notary_status=""
    if [[ -f "$state_file" ]]; then
        notary_status=$(kp_notary_json_field status < "$state_file" 2>/dev/null) || notary_status=""
    fi
    if [[ -f "$state_file" && "$notary_status" != "accepted" ]]; then
        echo "   Notarization did not complete; the app was NOT deployed to /Applications." >&2
        echo "   Recovery state: $state_file" >&2
        echo "   Resume without rebuilding once credentials/Apple are sorted:" >&2
        echo "   Scripts/release-candidate.sh --resume-notarization" >&2
    fi
    exit "$build_status"
fi

if [[ "$VERIFY" == "1" ]]; then
    "$SCRIPT_DIR/verify-installed-app.sh"
else
    echo "⏭️  Skipping installed-app verification (--no-verify)"
fi
