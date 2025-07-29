#!/bin/bash

# Kanata Launch Diagnostic Script
# This script helps diagnose why Kanata isn't launching or staying alive

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kanata Launch Diagnostic ===${NC}"
echo

# 1. Check if Kanata is installed
echo -e "${BLUE}1. Checking Kanata installation...${NC}"
if command -v kanata &> /dev/null; then
    KANATA_PATH=$(which kanata)
    echo -e "${GREEN}✓ Kanata found at: $KANATA_PATH${NC}"
    echo "Version info:"
    kanata --version 2>&1 || echo "Could not get version"
else
    echo -e "${RED}✗ Kanata not found in PATH${NC}"
    echo "Looking for common locations..."
    for path in "/usr/local/bin/kanata" "/opt/homebrew/bin/kanata" "$HOME/.cargo/bin/kanata"; do
        if [[ -f "$path" ]]; then
            echo "Found at: $path"
            KANATA_PATH="$path"
        fi
    done
fi
echo

# 2. Check for existing Kanata processes
echo -e "${BLUE}2. Checking for existing Kanata processes...${NC}"
if pgrep -f kanata > /dev/null; then
    echo -e "${YELLOW}⚠ Found running Kanata processes:${NC}"
    ps aux | grep kanata | grep -v grep
    echo
    echo "PIDs:"
    pgrep -f kanata
else
    echo -e "${GREEN}✓ No existing Kanata processes found${NC}"
fi
echo

# 3. Check configuration file
echo -e "${BLUE}3. Checking KeyPath configuration...${NC}"
CONFIG_PATH="$HOME/Library/Application Support/KeyPath/keypath.kbd"
if [[ -f "$CONFIG_PATH" ]]; then
    echo -e "${GREEN}✓ Config file exists at: $CONFIG_PATH${NC}"
    echo "Config content:"
    echo "---"
    cat "$CONFIG_PATH"
    echo "---"
    echo
    echo "Validating config..."
    if [[ -n "$KANATA_PATH" ]]; then
        if $KANATA_PATH --cfg "$CONFIG_PATH" --check 2>&1; then
            echo -e "${GREEN}✓ Config is valid${NC}"
        else
            echo -e "${RED}✗ Config validation failed${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Config file not found at: $CONFIG_PATH${NC}"
fi
echo

# 4. Check permissions
echo -e "${BLUE}4. Checking permissions...${NC}"
echo "Checking TCC database for permissions..."

# Check Input Monitoring
echo -n "Input Monitoring for kanata: "
if sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceListenEvent' AND auth_value=2;" 2>/dev/null | grep -q kanata; then
    echo -e "${GREEN}✓ Granted${NC}"
else
    echo -e "${RED}✗ Not granted${NC}"
fi

# Check Accessibility
echo -n "Accessibility for kanata: "
if sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND auth_value=2;" 2>/dev/null | grep -q kanata; then
    echo -e "${GREEN}✓ Granted${NC}"
else
    echo -e "${RED}✗ Not granted${NC}"
fi
echo

# 5. Check log file
echo -e "${BLUE}5. Checking Kanata log...${NC}"
LOG_PATH="$HOME/Library/Logs/KeyPath/kanata.log"
if [[ -f "$LOG_PATH" ]]; then
    echo "Last 20 lines of log:"
    echo "---"
    tail -20 "$LOG_PATH"
    echo "---"
else
    echo -e "${YELLOW}⚠ Log file not found at: $LOG_PATH${NC}"
fi
echo

# 6. Test manual launch
echo -e "${BLUE}6. Testing manual Kanata launch...${NC}"
if [[ -n "$KANATA_PATH" ]] && [[ -f "$CONFIG_PATH" ]]; then
    echo "Attempting to launch Kanata manually..."
    echo "Command: $KANATA_PATH --cfg \"$CONFIG_PATH\" --watch"
    echo
    echo "Press Ctrl+C to stop the test"
    echo "---"
    $KANATA_PATH --cfg "$CONFIG_PATH" --watch 2>&1 | head -50
else
    echo -e "${YELLOW}⚠ Cannot test - missing kanata binary or config${NC}"
fi

echo
echo -e "${BLUE}=== Diagnostic Complete ===${NC}"
echo
echo "Common issues:"
echo "1. Missing permissions - Grant both Input Monitoring and Accessibility"
echo "2. Invalid config - Check the validation output above"
echo "3. Conflicting processes - Kill existing kanata processes"
echo "4. Path issues - Ensure kanata is at /usr/local/bin/kanata"