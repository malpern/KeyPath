#!/bin/bash
set -euo pipefail

# A missing rg exits 127, which the if below would read as "no hits".
command -v rg >/dev/null || { echo "❌ ripgrep (rg) is required" >&2; exit 1; }

FILE="Sources/KeyPathAppKit/InstallationWizard/Core/WizardAutoFixer.swift"
if rg --no-heading "SubprocessRunner|PrivilegedOperationsCoordinator|launchctl|osascript" "$FILE" > /tmp/autofixer-badrefs.txt; then
  echo "❌ Forbidden API found in $FILE:" >&2
  cat /tmp/autofixer-badrefs.txt >&2
  exit 1
fi

echo "✅ WizardAutoFixer clean (no direct subprocess/privileged calls)"
