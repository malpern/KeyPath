#!/usr/bin/env bash
# Lint script to detect façade bypasses in WizardAutoFixer.
# 
# Issue: https://github.com/malpern/KeyPath/issues/47
#
# WizardAutoFixer should route all privileged operations through InstallerEngine
# and PrivilegeBroker/PrivilegedOperationsCoordinator. Direct subprocess calls
# or AppleScript execution would bypass the façade.
#
# Allowed patterns:
# - SubprocessRunner for non-privileged operations (runCommand for process checks)
# - NSAppleScript for UI-related tasks (opening System Settings, etc.)
#
# Disallowed patterns:
# - pkill, launchctl, installer, or other system commands for privileged ops
# - AppleScript with "with administrator privileges"

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
AUTOFIXER="$ROOT/Sources/KeyPathAppKit/InstallationWizard/Core/WizardAutoFixer.swift"

if [ ! -f "$AUTOFIXER" ]; then
  echo "❌ WizardAutoFixer.swift not found at expected path"
  exit 1
fi

VIOLATIONS=0
VIOLATION_DETAILS=""
APPLEADMIN_HITS=""
PKILL_HITS=""
LAUNCHCTL_HITS=""
INSTALLER_HITS=""
SUDO_HITS=""

# Check for direct subprocess calls that should go through coordinator
# Allowed: runCommand for checking if processes exist (kill -0 checks)
# Disallowed: privileged operations via subprocess
#
# EXCEPTION: resetEverything() is a documented "nuclear option" that intentionally
# bypasses the façade. Lines 529-573 contain the resetEverything function.

echo "🔍 Checking for façade bypasses in WizardAutoFixer..."
echo ""

# Get line numbers for the resetEverything function (nuclear option exception)
# It spans roughly lines 529-573 based on current code
NUCLEAR_START=529
NUCLEAR_END=573

# Helper function to check if a line number is in the nuclear option function
is_in_nuclear() {
  local line_num=$1
  if [ "$line_num" -ge "$NUCLEAR_START" ] && [ "$line_num" -le "$NUCLEAR_END" ]; then
    return 0  # true - is in nuclear option
  fi
  return 1  # false - not in nuclear option
}

# 1. Check for AppleScript with administrator privileges (privileged ops)
while IFS= read -r line; do
  line_num=$(echo "$line" | cut -d: -f1)
  if ! is_in_nuclear "$line_num"; then
    if [ -z "$APPLEADMIN_HITS" ]; then
      APPLEADMIN_HITS="$line"
    else
      APPLEADMIN_HITS="$APPLEADMIN_HITS\n$line"
    fi
  fi
done < <(grep -n "with administrator privileges" "$AUTOFIXER" 2>/dev/null || true)

if [ -n "$APPLEADMIN_HITS" ]; then
  echo "⚠️  Found AppleScript with administrator privileges:"
  echo -e "$APPLEADMIN_HITS"
  VIOLATION_DETAILS="$VIOLATION_DETAILS\n- AppleScript admin privileges (should use PrivilegedOperationsCoordinator)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# 2. Check for direct pkill calls for privileged termination (outside nuclear option)
while IFS= read -r line; do
  line_num=$(echo "$line" | cut -d: -f1)
  if ! is_in_nuclear "$line_num"; then
    if [ -z "$PKILL_HITS" ]; then
      PKILL_HITS="$line"
    else
      PKILL_HITS="$PKILL_HITS\n$line"
    fi
  fi
done < <(grep -n 'pkill.*-9' "$AUTOFIXER" 2>/dev/null || true)

if [ -n "$PKILL_HITS" ]; then
  echo "⚠️  Found direct pkill calls outside nuclear option:"
  echo -e "$PKILL_HITS"
  VIOLATION_DETAILS="$VIOLATION_DETAILS\n- Direct pkill (should use PrivilegedOperationsCoordinator.terminateProcess)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# 3. Check for direct launchctl calls (should use coordinator)
# Filter out: comments, log messages, and string literals in error messages
LAUNCHCTL_HITS=""
while IFS= read -r line; do
  # Skip lines that are comments or log messages
  if echo "$line" | grep -qE '(//|AppLogger|\.error\(|\.log\(|\.warn\(|\.info\()'; then
    continue
  fi
  line_num=$(echo "$line" | cut -d: -f1)
  if ! is_in_nuclear "$line_num"; then
    if [ -z "$LAUNCHCTL_HITS" ]; then
      LAUNCHCTL_HITS="$line"
    else
      LAUNCHCTL_HITS="$LAUNCHCTL_HITS\n$line"
    fi
  fi
done < <(grep -n 'launchctl' "$AUTOFIXER" 2>/dev/null || true)

if [ -n "$LAUNCHCTL_HITS" ]; then
  echo "⚠️  Found direct launchctl calls (excluding comments/logs):"
  echo -e "$LAUNCHCTL_HITS"
  VIOLATION_DETAILS="$VIOLATION_DETAILS\n- Direct launchctl (should use PrivilegedOperationsCoordinator)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# 4. Check for direct installer calls (pkg installation) - outside nuclear option
while IFS= read -r line; do
  line_num=$(echo "$line" | cut -d: -f1)
  if ! is_in_nuclear "$line_num"; then
    if [ -z "$INSTALLER_HITS" ]; then
      INSTALLER_HITS="$line"
    else
      INSTALLER_HITS="$INSTALLER_HITS\n$line"
    fi
  fi
done < <(grep -n '/usr/sbin/installer' "$AUTOFIXER" 2>/dev/null || true)

if [ -n "$INSTALLER_HITS" ]; then
  echo "⚠️  Found direct installer calls:"
  echo -e "$INSTALLER_HITS"
  VIOLATION_DETAILS="$VIOLATION_DETAILS\n- Direct installer (should use PrivilegedOperationsCoordinator)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# 5. Check for direct sudo calls - outside nuclear option
while IFS= read -r line; do
  line_num=$(echo "$line" | cut -d: -f1)
  if ! is_in_nuclear "$line_num"; then
    if [ -z "$SUDO_HITS" ]; then
      SUDO_HITS="$line"
    else
      SUDO_HITS="$SUDO_HITS\n$line"
    fi
  fi
done < <(grep -n '/usr/bin/sudo' "$AUTOFIXER" 2>/dev/null || true)

if [ -n "$SUDO_HITS" ]; then
  echo "⚠️  Found direct sudo calls outside nuclear option:"
  echo -e "$SUDO_HITS"
  VIOLATION_DETAILS="$VIOLATION_DETAILS\n- Direct sudo (should use PrivilegedOperationsCoordinator)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# Report results
echo ""
if [ $VIOLATIONS -eq 0 ]; then
  echo "✅ No façade bypasses detected in WizardAutoFixer."
  echo ""
  echo "Summary:"
  echo "  - AppleScript admin privileges: None found ✓"
  echo "  - Direct pkill (outside nuclear): None found ✓"
  echo "  - Direct launchctl: None found ✓"
  echo "  - Direct installer: None found ✓"
  echo "  - Direct sudo (outside nuclear): None found ✓"
  exit 0
else
  echo "❌ Found $VIOLATIONS potential façade bypass(es) in WizardAutoFixer:"
  echo -e "$VIOLATION_DETAILS"
  echo ""
  echo "These operations should route through:"
  echo "  - PrivilegedOperationsCoordinator (for privileged operations)"
  echo "  - InstallerEngine + PrivilegeBroker (for auto-fix recipes)"
  echo ""
  echo "See: https://github.com/malpern/KeyPath/issues/47"
  exit 1
fi
