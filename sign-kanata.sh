#!/bin/bash

# Script to properly code-sign the kanata binary
# This is required for macOS to allow kanata to access keyboard devices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kanata Code Signing Script ===${NC}"
echo

# Check if kanata is installed
KANATA_PATH="/usr/local/bin/kanata"
if [[ ! -f "$KANATA_PATH" ]]; then
    echo -e "${RED}Error: Kanata not found at $KANATA_PATH${NC}"
    echo "Please install kanata first: brew install kanata"
    exit 1
fi

echo -e "${GREEN}✓ Found kanata at: $KANATA_PATH${NC}"

# Check current signing status
echo -e "\n${BLUE}Current signing status:${NC}"
codesign -d -vvv "$KANATA_PATH" 2>&1 | grep -E "Signature|TeamIdentifier|Identifier" || true

# Sign with Developer ID
echo -e "\n${BLUE}Signing kanata with Developer ID...${NC}"
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Remove any existing signature
echo "Removing existing signature..."
codesign --remove-signature "$KANATA_PATH" 2>/dev/null || true

# Sign with runtime hardening and required entitlements
echo "Applying new signature..."
codesign --force \
    --options=runtime \
    --sign "$SIGNING_IDENTITY" \
    --identifier "com.keypath.kanata" \
    --timestamp \
    "$KANATA_PATH"

# Verify the signature
echo -e "\n${BLUE}Verifying signature...${NC}"
if codesign -dvvv "$KANATA_PATH" 2>&1 | grep -q "Developer ID"; then
    echo -e "${GREEN}✓ Successfully signed with Developer ID${NC}"
else
    echo -e "${RED}✗ Signing verification failed${NC}"
    exit 1
fi

# Check Gatekeeper approval
echo -e "\n${BLUE}Checking Gatekeeper approval...${NC}"
if spctl -a -vvv "$KANATA_PATH" 2>&1; then
    echo -e "${GREEN}✓ Gatekeeper accepts the signature${NC}"
else
    echo -e "${YELLOW}⚠ Gatekeeper assessment failed (may need notarization)${NC}"
fi

echo -e "\n${GREEN}=== Signing Complete ===${NC}"
echo
echo "The kanata binary has been properly signed."
echo "You should now be able to launch it without privilege violations."
echo
echo "Next steps:"
echo "1. Restart KeyPath.app"
echo "2. The signed kanata should now work properly"