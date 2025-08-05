#!/bin/bash

# run-tests-automated.sh
# Automated test runner with passwordless sudo setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_ON_EXIT=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 KeyPath Automated Test Runner${NC}"
echo "================================================="

# Function to cleanup on exit
cleanup() {
    if [ "$CLEANUP_ON_EXIT" = true ]; then
        echo -e "\n${YELLOW}🧹 Cleaning up test environment...${NC}"
        "$SCRIPT_DIR/Scripts/cleanup-test-sudoers.sh" || true
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Check if running in CI/testing environment
if [ "$CI" = "true" ] || [ "$KEYPATH_TESTING" = "true" ] || [ "$1" = "--auto-setup" ]; then
    echo -e "${YELLOW}🔧 Setting up passwordless sudo for testing...${NC}"
    "$SCRIPT_DIR/Scripts/setup-test-sudoers.sh"
    echo ""
else
    echo -e "${YELLOW}⚠️  This script will set up passwordless sudo for testing.${NC}"
    echo "This is potentially less secure and should only be used in development."
    echo ""
    read -p "Continue with automated setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Test setup cancelled."
        exit 1
    fi
    
    "$SCRIPT_DIR/Scripts/setup-test-sudoers.sh"
    echo ""
fi

echo -e "${BLUE}🏃 Running Tests...${NC}"
echo "------------------------------------------------"

# Run Swift tests
echo -e "${BLUE}1. Running Swift Unit Tests...${NC}"
if swift test; then
    echo -e "${GREEN}✅ Swift tests passed${NC}"
else
    echo -e "${RED}❌ Swift tests failed${NC}"
    exit 1
fi

echo ""

# Run integration tests
echo -e "${BLUE}2. Running Integration Tests...${NC}"

echo -e "${BLUE}   → Kanata System Tests${NC}"
if "$SCRIPT_DIR/test-kanata-system.sh"; then
    echo -e "${GREEN}   ✅ Kanata system tests passed${NC}"
else
    echo -e "${RED}   ❌ Kanata system tests failed${NC}"
    exit 1
fi

echo -e "${BLUE}   → Hot Reload Tests${NC}"
if "$SCRIPT_DIR/test-hot-reload.sh"; then
    echo -e "${GREEN}   ✅ Hot reload tests passed${NC}"
else
    echo -e "${RED}   ❌ Hot reload tests failed${NC}"
    exit 1
fi

echo -e "${BLUE}   → Service Status Tests${NC}"
if "$SCRIPT_DIR/test-service-status.sh"; then
    echo -e "${GREEN}   ✅ Service status tests passed${NC}"
else
    echo -e "${RED}   ❌ Service status tests failed${NC}"
    exit 1
fi

echo -e "${BLUE}   → Installer Tests${NC}"
if "$SCRIPT_DIR/test-installer.sh"; then
    echo -e "${GREEN}   ✅ Installer tests passed${NC}"
else
    echo -e "${RED}   ❌ Installer tests failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 All Tests Passed!${NC}"
echo "================================================="

# Option to keep sudoers for development
if [ "$CI" != "true" ] && [ "$KEYPATH_TESTING" != "true" ]; then
    echo ""
    read -p "Keep passwordless sudo setup for continued development? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_ON_EXIT=false
        echo -e "${YELLOW}⚠️  Passwordless sudo kept active${NC}"
        echo "Remember to run: $SCRIPT_DIR/Scripts/cleanup-test-sudoers.sh when done"
    fi
fi