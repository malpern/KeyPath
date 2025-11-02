#!/bin/bash
set -e

# Consolidated: this script now delegates to the canonical entry at repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/Scripts}"

echo "Deprecated: use ./build.sh from the repository root. Redirecting..." >&2
exec "$REPO_ROOT/build.sh" "$@"