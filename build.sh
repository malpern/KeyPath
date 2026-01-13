#!/bin/bash
set -euo pipefail

# Canonical build entry point: delegates to Scripts/build-and-sign.sh
# This builds, signs, notarizes (unless SKIP_NOTARIZE=1), deploys to ~/Applications, and restarts the app.
#
# Usage:
#   ./build.sh                               # Full build with notarization
#   SKIP_NOTARIZE=1 ./build.sh               # Skip notarization for faster local testing
#   SKIP_NOTARIZE=1 SKIP_CODESIGN=1 ./build.sh  # Skip notarization + codesign for local dev

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)

# Pass through SKIP_NOTARIZE environment variable if set
if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
    SKIP_NOTARIZE=1 "$SCRIPT_DIR/Scripts/build-and-sign.sh"
else
    "$SCRIPT_DIR/Scripts/build-and-sign.sh"
fi
