#!/bin/bash
set -euo pipefail

# Device-level installer smoke. No privileged changes unless KEYPATH_ALLOW_PRIV=1.
# Usage:
#   KEYPATH_E2E_DEVICE=1 ./Scripts/test-installer-device.sh
#   KEYPATH_E2E_DEVICE=1 KEYPATH_ALLOW_PRIV=1 ./Scripts/test-installer-device.sh   # allows repair runs (not currently performed)

if [ "${KEYPATH_E2E_DEVICE:-0}" != "1" ]; then
  echo "🔇 Skipping: set KEYPATH_E2E_DEVICE=1 to run device installer smoke."
  exit 0
fi

echo "🧪 Device installer smoke (non-destructive)..."

# 1) Inspect system via InstallerEngine through swift test filter (runs fast, no side effects)
swift test --filter InstallerDeviceTests || exit_code=$?
if [ "${exit_code:-0}" != "0" ]; then
  echo "❌ InstallerDeviceTests failed (code ${exit_code:-0})"
  exit "${exit_code:-1}"
fi

echo "✅ Installer device smoke complete."
