#!/bin/bash
set -e

# Consolidated: this script now delegates to the canonical entry at repo root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Deprecated: use ./build.sh from the repository root. Redirecting..." >&2
exec "$SCRIPT_DIR/build.sh" "$@"