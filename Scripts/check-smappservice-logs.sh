#!/bin/bash

# Quick script to check SMAppService registration status and logs

echo "🔍 SMAppService Registration Check"
echo "==================================="
echo ""

echo "1. SMAppService Status:"
swift run smappservice-poc com.keypath.kanata.plist status 2>&1 | grep -E "status=|SMAppService"
echo ""

echo "2. launchctl Status:"
if launchctl print system/com.keypath.kanata >/dev/null 2>&1; then
    echo "   ✅ launchctl reports service"
    launchctl print system/com.keypath.kanata 2>&1 | head -5
else
    echo "   ⚠️  launchctl does not report service"
fi
echo ""

echo "3. Legacy Plist Check:"
if [ -f "/Library/LaunchDaemons/com.keypath.kanata.plist" ]; then
    echo "   ⚠️  Legacy plist found (launchctl path)"
    ls -la /Library/LaunchDaemons/com.keypath.kanata.plist
else
    echo "   ✅ No legacy plist (SMAppService path)"
fi
echo ""

echo "4. Recent App Logs (SMAppService related):"
log show --style syslog --last 10m --predicate 'process == "KeyPath"' 2>&1 | \
    grep -i "smappservice\|kanatadaemon\|feature.*flag\|using.*path\|registering" | \
    tail -20 || echo "   (No recent SMAppService logs found)"
echo ""

echo "5. Registration Method Summary:"
SMAPP_STATUS=$(swift run smappservice-poc com.keypath.kanata.plist status 2>&1 | grep -o "status=[0-9]" | cut -d= -f2)
LAUNCHCTL_EXISTS=$(launchctl print system/com.keypath.kanata >/dev/null 2>&1 && echo "yes" || echo "no")
LEGACY_PLIST=$(test -f /Library/LaunchDaemons/com.keypath.kanata.plist && echo "yes" || echo "no")

echo "   SMAppService status: $SMAPP_STATUS (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)"
echo "   launchctl service: $LAUNCHCTL_EXISTS"
echo "   Legacy plist: $LEGACY_PLIST"
echo ""

if [ "$SMAPP_STATUS" = "1" ] && [ "$LEGACY_PLIST" = "no" ]; then
    echo "   ✅ SMAppService registration confirmed!"
elif [ "$LAUNCHCTL_EXISTS" = "yes" ] && [ "$LEGACY_PLIST" = "yes" ]; then
    echo "   ⚠️  Using launchctl path (legacy)"
else
    echo "   ⚠️  Mixed state - check logs above"
fi

