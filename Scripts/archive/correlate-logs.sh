#!/bin/bash
# correlate-logs.sh - Correlate KeyPath and Kanata logs for debugging broken pipe issues
#
# Usage:
#   ./correlate-logs.sh [time_pattern]
#
# Examples:
#   ./correlate-logs.sh "22:05:25"   # Analyze specific time
#   ./correlate-logs.sh              # Show last 50 lines from each log

set -euo pipefail

TIME_PATTERN="${1:-}"
KEYPATH_LOG="$HOME/Library/Logs/KeyPath/keypath-debug.log"
KANATA_STDOUT="/var/log/com.keypath.kanata.stdout.log"
KANATA_STDERR="/var/log/com.keypath.kanata.stderr.log"

echo "======================================================================"
echo "KeyPath + Kanata Log Correlation"
echo "======================================================================"
echo ""

if [ -n "$TIME_PATTERN" ]; then
  echo "=== Filtering for time: $TIME_PATTERN ==="
  echo ""

  echo "--- KeyPath Logs (TCP + Reload) ---"
  grep "$TIME_PATTERN" "$KEYPATH_LOG" 2>/dev/null | grep -E "(TCP|Reload|⏱️|🔌)" || echo "No KeyPath logs found"
  echo ""

  echo "--- Kanata Logs (Reload operations) ---"
  grep "$TIME_PATTERN" "$KANATA_STDOUT" 2>/dev/null | grep -E "Reload:" || echo "No Kanata reload logs found"
  echo ""

  echo "--- Kanata Errors ---"
  grep "$TIME_PATTERN" "$KANATA_STDERR" 2>/dev/null || echo "No Kanata errors found"
  echo ""
else
  echo "=== Showing last 50 lines from each log ==="
  echo ""

  echo "--- KeyPath Logs (TCP + Reload) ---"
  grep -E "(TCP|Reload|⏱️|🔌)" "$KEYPATH_LOG" 2>/dev/null | tail -50 || echo "No KeyPath logs found"
  echo ""

  echo "--- Kanata Logs (Reload operations) ---"
  grep "Reload:" "$KANATA_STDOUT" 2>/dev/null | tail -30 || echo "No Kanata reload logs found"
  echo ""

  echo "--- Recent Kanata Errors ---"
  tail -20 "$KANATA_STDERR" 2>/dev/null || echo "No Kanata errors found"
  echo ""
fi

echo "======================================================================"
echo "Statistics"
echo "======================================================================"
echo "Broken pipe errors (all time): $(grep -c "Broken pipe" "$KANATA_STDERR" 2>/dev/null || echo 0)"
echo "Successful ReloadResult sends: $(grep -c "ReloadResult sent successfully" "$KANATA_STDOUT" 2>/dev/null || echo 0)"
echo "Connection state changes: $(grep -c "Connection state changed" "$KEYPATH_LOG" 2>/dev/null || echo 0)"
echo "Connection reuses: $(grep -c "Reusing existing connection" "$KEYPATH_LOG" 2>/dev/null || echo 0)"
echo "New connections: $(grep -c "Creating new connection" "$KEYPATH_LOG" 2>/dev/null || echo 0)"
