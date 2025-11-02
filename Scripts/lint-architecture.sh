#!/bin/bash
set -euo pipefail

# Architecture safety lints to enforce critical invariants without shouting in comments

fail=0

echo "🔎 Running architecture safety lints..."

# 1) IOHIDCheckAccess must only be used inside Services/PermissionOracle.swift
if grep -R --line-number -e 'IOHIDCheckAccess\(' "Sources/KeyPath" | grep -v 'Sources/KeyPath/Services/PermissionOracle.swift' >/dev/null 2>&1; then
  echo "❌ IOHIDCheckAccess must only be referenced in Sources/KeyPath/Services/PermissionOracle.swift"
  echo "Offending references:"
  grep -R --line-number -e 'IOHIDCheckAccess\(' "Sources/KeyPath" | grep -v 'Sources/KeyPath/Services/PermissionOracle.swift' || true
  fail=1
else
  echo "✅ IOHIDCheckAccess usage limited to PermissionOracle.swift"
fi

# 2) Ensure osascript installer path explicitly uses bundled kanata
if ! grep -q "Using bundled kanata binary" "Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"; then
  echo "❌ LaunchDaemonInstaller.swift must echo 'Using bundled kanata binary' in osascript path"
  fail=1
else
  echo "✅ LaunchDaemonInstaller osascript path references bundled kanata"
fi

exit $fail


