#!/bin/bash

# Diagnose Swift build hang issue
# Based on research of common causes in 2024

set -e

echo "🔍 KeyPath Build Hang Diagnosis"
echo "================================"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_found() {
    echo -e "${YELLOW}[FOUND]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_issue() {
    echo -e "${RED}[ISSUE]${NC} $1"
}

echo "Checking common causes of build hangs..."
echo ""

# 1. Check DerivedData corruption
print_check "Checking DerivedData corruption..."
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"
KEYPATH_DERIVED=$(find "$DERIVED_DATA_PATH" -name "*KeyPath*" -o -name "*Keypath*" 2>/dev/null | head -1)

if [ -n "$KEYPATH_DERIVED" ]; then
    print_found "Found DerivedData: $KEYPATH_DERIVED"
    DERIVED_SIZE=$(du -sh "$KEYPATH_DERIVED" | cut -f1)
    print_found "Size: $DERIVED_SIZE"
    
    # Check if it's unusually large (>500MB is suspicious)
    DERIVED_SIZE_MB=$(du -sm "$KEYPATH_DERIVED" | cut -f1)
    if [ "$DERIVED_SIZE_MB" -gt 500 ]; then
        print_issue "DerivedData is suspiciously large (${DERIVED_SIZE_MB}MB)"
        echo "  Solution: rm -rf \"$KEYPATH_DERIVED\""
    else
        print_ok "DerivedData size looks normal"
    fi
else
    print_ok "No existing DerivedData found"
fi

# 2. Check .build directory corruption
print_check "Checking .build directory..."
if [ -d ".build" ]; then
    BUILD_SIZE=$(du -sh .build | cut -f1)
    print_found "Found .build directory: $BUILD_SIZE"
    
    # Check for stuck processes
    SWIFT_PROCESSES=$(ps aux | grep -v grep | grep -c "swift\|swiftc" || true)
    if [ "$SWIFT_PROCESSES" -gt 0 ]; then
        print_issue "Found $SWIFT_PROCESSES running Swift processes"
        echo "  These might be stuck from previous builds"
        ps aux | grep -v grep | grep "swift\|swiftc" | awk '{print "  PID " $2 ": " $11 " " $12 " " $13}'
    else
        print_ok "No stuck Swift processes"
    fi
else
    print_ok "No .build directory"
fi

# 3. Check for complex code that could cause type inference issues
print_check "Checking for complex code patterns..."

# Look for large array/dictionary literals
LARGE_LITERALS=$(find Sources -name "*.swift" -exec grep -l "\[.*:.*," {} \; 2>/dev/null | wc -l)
if [ "$LARGE_LITERALS" -gt 0 ]; then
    print_found "Found $LARGE_LITERALS files with potential dictionary literals"
    find Sources -name "*.swift" -exec grep -l "\[.*:.*," {} \; 2>/dev/null | head -3 | while read file; do
        echo "  $file"
    done
fi

# Look for very long lines (>200 chars) that might cause inference issues
LONG_LINES=$(find Sources -name "*.swift" -exec awk 'length($0) > 200 {print FILENAME":"NR":"$0}' {} \; 2>/dev/null | wc -l)
if [ "$LONG_LINES" -gt 0 ]; then
    print_found "Found $LONG_LINES very long lines that might cause type inference issues"
fi

# 4. Check git status for recent changes
print_check "Checking recent changes..."
CHANGED_FILES=$(git status --porcelain | wc -l)
if [ "$CHANGED_FILES" -gt 0 ]; then
    print_found "Found $CHANGED_FILES changed files since last commit"
    echo "  Recent changes might contain problematic code patterns"
    git status --porcelain | head -5 | while read line; do
        echo "  $line"
    done
else
    print_ok "No uncommitted changes"
fi

# 5. Check for SPM-specific issues
print_check "Checking Package.swift structure..."
if grep -q "swift-tools-version.*6\." Package.swift; then
    TOOLS_VERSION=$(grep "swift-tools-version" Package.swift | head -1)
    print_found "Using Swift tools version: $TOOLS_VERSION"
    print_issue "Swift 6.x tools version might have compatibility issues"
    echo "  Consider changing to: // swift-tools-version: 5.9"
fi

# Check package dependencies
DEPS=$(grep -A 20 "dependencies:" Package.swift | grep -c "package(" || echo "0")
if [ "$DEPS" -eq 0 ]; then
    print_ok "No external dependencies (good for avoiding SPM issues)"
else
    print_found "Found $DEPS package dependencies"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🛠️  RECOMMENDED FIXES (try in order):"
echo ""

echo "1. Clear DerivedData and .build:"
echo "   rm -rf ~/.build ~/Library/Developer/Xcode/DerivedData/*KeyPath*"
echo ""

echo "2. Kill any stuck Swift processes:"
echo "   sudo pkill -f swift"
echo ""

echo "3. Try incremental build instead of clean build:"
echo "   swift build -c release --product KeyPath"
echo ""

echo "4. If that fails, change Package.swift tools version:"
echo "   Edit line 1: // swift-tools-version: 5.9"
echo ""

echo "5. Temporarily remove optimizations:"
echo "   Edit Package.swift, remove .unsafeFlags([\"-suppress-warnings\"])"
echo ""

echo "6. Try Xcode build instead of SPM:"
echo "   swift package generate-xcodeproj"
echo "   open KeyPath.xcodeproj"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Offer to run quick fixes
echo ""
read -p "Run quick fixes automatically? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running quick fixes..."
    
    # Fix 1: Clear caches
    echo "Clearing build caches..."
    rm -rf .build
    find ~/Library/Developer/Xcode/DerivedData -name "*KeyPath*" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Fix 2: Kill swift processes
    echo "Killing any stuck Swift processes..."
    sudo pkill -f swift 2>/dev/null || true
    
    # Fix 3: Try build
    echo "Attempting build..."
    timeout 60 swift build -c release --product KeyPath || echo "Build timed out - this confirms the hang issue"
    
    echo "Quick fixes applied. Try building again."
fi