#!/bin/bash
set -euo pipefail

FILE="Sources/KeyPathAppKit/InstallationWizard/Core/WizardAutoFixer.swift"
if rg --no-heading "SubprocessRunner|PrivilegedOperationsCoordinator|launchctl|osascript" "$FILE" > /tmp/autofixer-badrefs.txt; then
  echo "❌ Forbidden API found in $FILE:" >&2
  cat /tmp/autofixer-badrefs.txt >&2
  exit 1
fi

echo "✅ WizardAutoFixer clean (no direct subprocess/privileged calls)"
