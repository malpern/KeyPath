#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

# Disallow Task.sleep in wizard code; allow tests and non-wizard targets.
if rg "Task\\.sleep" "$ROOT/Sources/KeyPathAppKit/InstallationWizard" "$ROOT/Sources/KeyPathWizardCore" >/tmp/lint_no_sleep_hits 2>/dev/null; then
  echo "❌ Task.sleep found in wizard sources:"
  cat /tmp/lint_no_sleep_hits
  echo "Replace with readiness polling / health checks."
  exit 1
fi

echo "✅ No Task.sleep in wizard sources."
