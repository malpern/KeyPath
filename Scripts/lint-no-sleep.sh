#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

# Disallow Task.sleep in wizard code and Swift tests.
if rg "Task\\.sleep" "$ROOT/Sources/KeyPathAppKit/InstallationWizard" "$ROOT/Sources/KeyPathWizardCore" >/tmp/lint_no_sleep_hits 2>/dev/null; then
  echo "❌ Task.sleep found in wizard sources:"
  cat /tmp/lint_no_sleep_hits
  echo "Replace with readiness polling / health checks."
  exit 1
fi

if rg "Task\\.sleep|Thread\\.sleep|usleep" "$ROOT/Tests" -g '*.swift' >/tmp/lint_no_sleep_hits 2>/dev/null; then
  echo "❌ Real sleeps found in Swift tests:"
  cat /tmp/lint_no_sleep_hits
  echo "Use injected clocks, expectations, Task.yield(), or DEBUG-only drains instead."
  exit 1
fi

echo "✅ No Task.sleep in wizard sources."
echo "✅ No real sleeps in Swift tests."
