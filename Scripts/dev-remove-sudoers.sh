#!/bin/bash
#
# dev-remove-sudoers.sh - Remove KeyPath development sudoers configuration
#
# This script removes the NOPASSWD rules created by dev-setup-sudoers.sh.
# Run this BEFORE making any public releases!
#
# Usage:
#   sudo ./Scripts/dev-remove-sudoers.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SUDOERS_FILE="/etc/sudoers.d/keypath-dev"

echo "=================================================="
echo "KeyPath Development Sudoers Removal"
echo "=================================================="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if file exists
if [ ! -f "$SUDOERS_FILE" ]; then
    echo -e "${YELLOW}Note: $SUDOERS_FILE does not exist${NC}"
    echo "Nothing to remove - sudoers is clean."
    exit 0
fi

# Show current contents
echo "Current contents of $SUDOERS_FILE:"
echo "-----------------------------------"
cat "$SUDOERS_FILE"
echo "-----------------------------------"
echo ""

# Confirm removal
read -p "Remove this file? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Remove the file
rm -f "$SUDOERS_FILE"

echo ""
echo -e "${GREEN}✅ Sudoers configuration removed successfully!${NC}"
echo ""
echo "Privileged operations will now require password prompts or osascript dialogs."
echo ""

# Verify removal
if [ -f "$SUDOERS_FILE" ]; then
    echo -e "${RED}Warning: File still exists - removal may have failed${NC}"
    exit 1
fi

echo "Safe to make public release."
