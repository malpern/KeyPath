#!/bin/bash
set -euo pipefail

# Canonical build entry point: delegates to Scripts/build-and-sign.sh
# This builds, signs, notarizes, deploys to ~/Applications, and restarts the app.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
"$SCRIPT_DIR/Scripts/build-and-sign.sh"