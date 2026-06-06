#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."

VERIFY=1
DOCTOR=1

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
  -h, --help          Show this help.

Environment:
  CODESIGN_IDENTITY   Developer ID Application identity override.
  NOTARY_PROFILE      notarytool keychain profile override.
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

"$SCRIPT_DIR/build-and-sign.sh"

if [[ "$VERIFY" == "1" ]]; then
    "$SCRIPT_DIR/verify-installed-app.sh"
else
    echo "⏭️  Skipping installed-app verification (--no-verify)"
fi
