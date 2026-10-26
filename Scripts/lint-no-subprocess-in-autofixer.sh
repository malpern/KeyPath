#!/bin/bash
set -euo pipefail

# A missing rg exits 127, which would otherwise read as "no hits".
command -v rg >/dev/null || { echo "❌ ripgrep (rg) is required" >&2; exit 1; }

FILE="Sources/KeyPathAppKit/InstallationWizard/Core/WizardAutoFixer.swift"
if [[ ! -e "$FILE" ]]; then
  # WizardAutoFixer was removed in favour of InstallerEngine.runSingleAction().
  echo "✅ $FILE no longer exists; nothing to check"
  exit 0
fi

# rg exits 0 on a match, 1 on none, and 2 on an error. Only 1 is a pass.
rc=0
rg --no-heading "SubprocessRunner|PrivilegedOperationsCoordinator|launchctl|osascript" "$FILE" > /tmp/autofixer-badrefs.txt || rc=$?
if (( rc == 0 )); then
  echo "❌ Forbidden API found in $FILE:" >&2
  cat /tmp/autofixer-badrefs.txt >&2
  exit 1
elif (( rc > 1 )); then
  echo "❌ rg failed on $FILE (exit $rc)" >&2
  exit 1
fi

echo "✅ WizardAutoFixer clean (no direct subprocess/privileged calls)"
