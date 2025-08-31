#!/bin/bash

echo "Testing system config creation..."

# Test 1: Check if user config exists
USER_CONFIG="$HOME/Library/Application Support/KeyPath/keypath.kbd"
echo "1. Checking user config at: $USER_CONFIG"
if [ -f "$USER_CONFIG" ]; then
    echo "   ✅ User config exists"
    echo "   Content preview:"
    head -3 "$USER_CONFIG" | sed 's/^/   /'
else
    echo "   ❌ User config missing"
    echo "   Creating default user config..."
    mkdir -p "$HOME/Library/Application Support/KeyPath"
    cat > "$USER_CONFIG" << EOF
(defcfg
  process-unmapped-keys yes
)

(defsrc caps)
(deflayer base esc)
EOF
    echo "   ✅ Created default user config"
fi

# Test 2: Try creating system config with admin privileges
SYSTEM_DIR="/usr/local/etc/kanata"
SYSTEM_CONFIG="/usr/local/etc/kanata/keypath.kbd"

echo "2. Creating system config at: $SYSTEM_CONFIG"
echo "   This will prompt for admin password..."

# Use osascript to create with admin privileges
osascript << EOF
do shell script "mkdir -p '$SYSTEM_DIR' && cp '$USER_CONFIG' '$SYSTEM_CONFIG'" with administrator privileges
EOF

if [ $? -eq 0 ]; then
    echo "   ✅ Admin command succeeded"
    if [ -f "$SYSTEM_CONFIG" ]; then
        echo "   ✅ System config file created successfully"
        echo "   Content preview:"
        head -3 "$SYSTEM_CONFIG" | sed 's/^/   /'
    else
        echo "   ❌ System config file not found after creation"
    fi
else
    echo "   ❌ Admin command failed"
fi

# Test 3: Check launchctl status
echo "3. Checking launchctl status:"
launchctl list | grep kanata | sed 's/^/   /'