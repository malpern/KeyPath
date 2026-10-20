#!/bin/bash
# Validate that every offline guide, local cross-link and image can be generated.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=$(mktemp -d)
trap 'rm -rf "$OUTPUT"' EXIT
python3 "$ROOT/Scripts/build-offline-help.py" --output "$OUTPUT"
