#!/bin/bash
# Extract validation timing data from KeyPath log file

LOG_FILE="$HOME/Library/Logs/KeyPath/keypath-debug.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Log file not found: $LOG_FILE"
    echo "   Make sure KeyPath has been run recently."
    exit 1
fi

echo "=== Validation Timing Report ==="
echo "Log file: $LOG_FILE"
echo ""

# Extract timing data
echo "=== Main Screen Validation (First Run) ==="
echo ""
grep -E "\[TIMING\].*Main screen|\[TIMING\].*Service wait|\[TIMING\].*Cache operations|\[TIMING\].*First-run overhead" "$LOG_FILE" | tail -10

echo ""
echo "=== Wizard Progress Bar Validation ==="
echo ""
grep -E "\[TIMING\].*Wizard" "$LOG_FILE" | tail -5

echo ""
echo "=== SystemValidator Step Timing ==="
echo ""
grep -E "\[TIMING\].*Step [1-5]|\[TIMING\].*Validation.*COMPLETE" "$LOG_FILE" | tail -10

echo ""
echo "=== Summary ==="
echo ""
echo "Main Screen Timing Breakdown:"
grep "\[TIMING\].*Service wait COMPLETE" "$LOG_FILE" | tail -1 | sed 's/.*COMPLETE: /  Service Wait: /'
grep "\[TIMING\].*Cache operations COMPLETE" "$LOG_FILE" | tail -1 | sed 's/.*COMPLETE: /  Cache Operations: /'
grep "\[TIMING\].*First-run overhead COMPLETE" "$LOG_FILE" | tail -1 | sed 's/.*COMPLETE: /  First-Run Overhead: /'
grep "\[TIMING\].*Main screen validation COMPLETE" "$LOG_FILE" | tail -1 | sed 's/.*COMPLETE: /  Validation: /'

echo ""
echo "Wizard Timing:"
grep "\[TIMING\].*Wizard validation COMPLETE" "$LOG_FILE" | tail -1 | sed 's/.*COMPLETE: /  Total: /'

echo ""
echo "Individual Step Timing (Latest Run):"
grep "\[TIMING\].*Step [1-5]" "$LOG_FILE" | tail -5 | sed 's/.*completed in /  /'

echo ""
echo "=== Full Timing Log (Last 50 lines) ==="
echo ""
grep "\[TIMING\]" "$LOG_FILE" | tail -50
