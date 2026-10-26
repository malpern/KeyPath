#!/usr/bin/env bash
set -euo pipefail

# A missing rg exits 127, which would otherwise read as "no hits".
command -v rg >/dev/null || { echo "❌ ripgrep (rg) is required" >&2; exit 1; }

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
HITS="$(mktemp)"
trap 'rm -f "$HITS"' EXIT

# rg exits 0 on a match, 1 on none, and 2 on an error such as a missing path.
# Only 1 is a pass.
search() {
  local rc=0
  rg "$@" >"$HITS" || rc=$?
  if (( rc > 1 )); then
    echo "❌ rg failed (exit $rc)" >&2
    exit 1
  fi
  return "$rc"
}

# Disallow Task.sleep in wizard code and Swift tests.
if search "Task\\.sleep" "$ROOT/Sources/KeyPathAppKit/InstallationWizard" "$ROOT/Sources/KeyPathWizardCore"; then
  echo "❌ Task.sleep found in wizard sources:"
  cat "$HITS"
  echo "Replace with readiness polling / health checks."
  exit 1
fi

if search "Task\\.sleep|Thread\\.sleep|usleep" "$ROOT/Tests" -g '*.swift'; then
  echo "❌ Real sleeps found in Swift tests:"
  cat "$HITS"
  echo "Use injected clocks, expectations, Task.yield(), or DEBUG-only drains instead."
  exit 1
fi

echo "✅ No Task.sleep in wizard sources."
echo "✅ No real sleeps in Swift tests."
