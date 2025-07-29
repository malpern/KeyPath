#!/bin/bash

# Reset kanata permissions after code signing
# The newly signed binary needs fresh permission grants

set -e

echo "🔐 Resetting kanata permissions after code signing..."
echo

# Reset TCC permissions for the kanata binary
echo "Removing existing TCC entries for kanata..."
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "DELETE FROM access WHERE client LIKE '%kanata%';" 2>/dev/null || true

echo "✅ TCC entries cleared"
echo
echo "🚨 IMPORTANT: You now need to:"
echo "1. Open System Settings > Privacy & Security"
echo "2. Go to 'Input Monitoring' and add kanata (/usr/local/bin/kanata)"
echo "3. Go to 'Accessibility' and add kanata (/usr/local/bin/kanata)"
echo "4. Restart KeyPath.app"
echo
echo "The newly signed kanata binary needs fresh permission grants."