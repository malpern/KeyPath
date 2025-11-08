#!/bin/bash

# Enhanced log viewer for SMAppService debugging
# Shows all the detailed debug logs we added

echo "🔍 SMAppService Debug Log Viewer"
echo "=================================="
echo ""

# Check recent logs for all our debug markers
echo "📋 Recent Activity (last 10 minutes):"
echo ""

log show --predicate 'process == "KeyPath"' --style syslog --last 10m 2>&1 | \
    grep -E "(LaunchDaemon|SMAppService|KanataDaemon|Feature|Using.*path|ENTRY POINT|registering|status|falling back)" | \
    tail -50

echo ""
echo "🔍 Feature Flag Checks:"
log show --predicate 'process == "KeyPath"' --style syslog --last 10m 2>&1 | \
    grep -E "Feature flag" | tail -10

echo ""
echo "🔍 SMAppService Registration Attempts:"
log show --predicate 'process == "KeyPath"' --style syslog --last 10m 2>&1 | \
    grep -E "(KanataDaemonManager|registering|SMAppService.*status|register\(\))" | tail -20

echo ""
echo "🔍 Path Selection (SMAppService vs launchctl):"
log show --predicate 'process == "KeyPath"' --style syslog --last 10m 2>&1 | \
    grep -E "(Using.*path|Feature flag is|ENTRY POINT)" | tail -15

echo ""
echo "🔍 Errors and Fallbacks:"
log show --predicate 'process == "KeyPath"' --style syslog --last 10m 2>&1 | \
    grep -E "(❌|⚠️|falling back|failed)" | tail -15

echo ""
echo "📊 Current Status:"
echo "=================="
./Scripts/check-smappservice-logs.sh 2>&1 | tail -20

