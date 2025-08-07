#!/bin/bash

echo "Installing experimental kanata to /usr/local/bin..."

# Backup existing kanata if it exists
if [ -f "/usr/local/bin/kanata" ]; then
    echo "Backing up existing kanata to /usr/local/bin/kanata.backup"
    sudo cp /usr/local/bin/kanata /usr/local/bin/kanata.backup
fi

# Copy experimental kanata to standard location
echo "Installing experimental kanata from:"
echo "  /Users/malpern/Library/CloudStorage/Dropbox/code/kanata-source/target/release/kanata"
echo "to:"
echo "  /usr/local/bin/kanata"

sudo cp /Users/malpern/Library/CloudStorage/Dropbox/code/kanata-source/target/release/kanata /usr/local/bin/kanata

# Make sure it's executable
sudo chmod +x /usr/local/bin/kanata

# Verify installation
echo ""
echo "Installation complete. Verification:"
/usr/local/bin/kanata --version

echo ""
echo "The experimental kanata is now installed at /usr/local/bin/kanata"
echo "The previous version (if any) is backed up at /usr/local/bin/kanata.backup"
echo ""
echo "Since this is the standard location, any existing permissions for"
echo "/usr/local/bin/kanata in System Settings should now apply to the"
echo "experimental version."