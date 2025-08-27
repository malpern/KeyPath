#!/bin/bash

# verify-refactor.sh
# Refactoring verification script - no permissions required
# Ensures build integrity and progress tracking throughout architectural changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 KeyPath Refactoring Verification"
echo "===================================="
echo "📁 Project: $PROJECT_DIR"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track verification results
CHECKS_PASSED=0
CHECKS_TOTAL=0

check() {
    local description="$1"
    local command="$2"
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    
    echo -n "🔍 $description... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        return 1
    fi
}

check_with_output() {
    local description="$1" 
    local command="$2"
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    
    echo "🔍 $description..."
    
    if eval "$command"; then
        echo -e "${GREEN}✅ PASS${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        return 1
    fi
}

# 1. Build Verification
echo -e "${BLUE}📦 Build Verification${NC}"
echo "==================="

check "Swift build (release)" "cd '$PROJECT_DIR' && swift build -c release"
check "Swift build (debug)" "cd '$PROJECT_DIR' && swift build"

echo ""

# 2. Code Structure Validation
echo -e "${BLUE}🏗️ Code Structure Validation${NC}"
echo "============================="

# Check that key files exist
check "KanataManager exists" "[ -f '$PROJECT_DIR/Sources/KeyPath/Managers/KanataManager.swift' ]"
check "PLAN.md exists" "[ -f '$PROJECT_DIR/PLAN.md' ]"
check "MANAGERS.md exists" "[ -f '$PROJECT_DIR/MANAGERS.md' ]"

# Check KanataManager line count (refactoring target)
if [ -f "$PROJECT_DIR/Sources/KeyPath/Managers/KanataManager.swift" ]; then
    KANATA_LINES=$(wc -l < "$PROJECT_DIR/Sources/KeyPath/Managers/KanataManager.swift")
    echo "📊 KanataManager line count: $KANATA_LINES"
    
    if [ $KANATA_LINES -gt 3500 ]; then
        echo -e "${RED}⚠️  KanataManager still very large (>3500 lines)${NC}"
    elif [ $KANATA_LINES -gt 1500 ]; then
        echo -e "${YELLOW}📉 KanataManager progress (1500-3500 lines)${NC}"
    elif [ $KANATA_LINES -gt 1000 ]; then
        echo -e "${BLUE}📉 KanataManager good progress (<1500 lines)${NC}"
    else
        echo -e "${GREEN}🎯 KanataManager target achieved (<1000 lines)${NC}"
    fi
fi

# Check for extension files (Milestone 1 indicator)
EXTENSION_COUNT=0
for ext in Lifecycle EventTaps Configuration Engine Output; do
    if [ -f "$PROJECT_DIR/Sources/KeyPath/Managers/KanataManager+$ext.swift" ]; then
        EXTENSION_COUNT=$((EXTENSION_COUNT + 1))
        echo "📄 Found KanataManager+$ext.swift"
    fi
done

if [ $EXTENSION_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ Milestone 1: KanataManager extensions found ($EXTENSION_COUNT/5)${NC}"
fi

echo ""

# 3. Test Validation
echo -e "${BLUE}🧪 Test Validation${NC}"
echo "=================="

check_with_output "Swift unit tests" "cd '$PROJECT_DIR' && swift test 2>&1 | tail -20"

echo ""

# 4. Import and Compilation Checks
echo -e "${BLUE}🔗 Import and Compilation Checks${NC}"
echo "================================"

# Check for common import issues after refactoring
check "No duplicate imports" "! grep -r 'import Foundation' '$PROJECT_DIR/Sources' | awk -F: '{print \$1}' | sort | uniq -d | grep -q ."
check "No circular imports" "cd '$PROJECT_DIR' && swift build 2>&1 | ! grep -q 'circular'"

# Check for protocol files (Milestone 2 indicator)
PROTOCOL_COUNT=0
if [ -d "$PROJECT_DIR/Sources/KeyPath/Core/Contracts" ]; then
    PROTOCOL_COUNT=$(find "$PROJECT_DIR/Sources/KeyPath/Core/Contracts" -name "*.swift" | wc -l)
    if [ $PROTOCOL_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅ Milestone 2: Protocol contracts found ($PROTOCOL_COUNT files)${NC}"
    fi
fi

echo ""

# 5. Manager Class Analysis
echo -e "${BLUE}📋 Manager Class Analysis${NC}"
echo "========================="

MANAGER_FILES=$(find "$PROJECT_DIR/Sources/KeyPath/Managers" -name "*Manager.swift" 2>/dev/null | wc -l)
echo "📊 Manager class count: $MANAGER_FILES"

# Check for large manager files
echo "📏 Manager file sizes:"
if [ -d "$PROJECT_DIR/Sources/KeyPath/Managers" ]; then
    for file in "$PROJECT_DIR/Sources/KeyPath/Managers"/*Manager.swift; do
        if [ -f "$file" ]; then
            lines=$(wc -l < "$file")
            filename=$(basename "$file")
            if [ $lines -gt 800 ]; then
                echo -e "   ${RED}$filename: $lines lines (large)${NC}"
            elif [ $lines -gt 400 ]; then
                echo -e "   ${YELLOW}$filename: $lines lines (medium)${NC}"
            else
                echo -e "   ${GREEN}$filename: $lines lines (good)${NC}"
            fi
        fi
    done
fi

echo ""

# 6. Refactoring Progress Assessment
echo -e "${BLUE}📊 Refactoring Progress Assessment${NC}"
echo "=================================="

MILESTONE_SCORE=0
MILESTONE_TOTAL=9

# Milestone 1: File splitting
if [ $EXTENSION_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ Milestone 1: File splitting ($EXTENSION_COUNT/5 extensions)${NC}"
    MILESTONE_SCORE=$((MILESTONE_SCORE + 1))
else
    echo -e "${YELLOW}⏳ Milestone 1: File splitting (not started)${NC}"
fi

# Milestone 2: Protocols
if [ $PROTOCOL_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ Milestone 2: Protocol contracts ($PROTOCOL_COUNT protocols)${NC}"
    MILESTONE_SCORE=$((MILESTONE_SCORE + 1))
else
    echo -e "${YELLOW}⏳ Milestone 2: Protocol contracts (not started)${NC}"
fi

# Check for service directories (Milestones 4+)
SERVICE_DIRS=0
for dir in Infrastructure Core Application; do
    if [ -d "$PROJECT_DIR/Sources/KeyPath/$dir" ]; then
        SERVICE_DIRS=$((SERVICE_DIRS + 1))
        echo -e "${GREEN}✅ Service directory: Sources/KeyPath/$dir${NC}"
    fi
done

if [ $SERVICE_DIRS -gt 0 ]; then
    echo -e "${GREEN}✅ Milestone 4+: Service extraction in progress${NC}"
    MILESTONE_SCORE=$((MILESTONE_SCORE + SERVICE_DIRS))
fi

echo ""
echo -e "${BLUE}📈 Overall Progress: $MILESTONE_SCORE/$MILESTONE_TOTAL milestones${NC}"

# Calculate progress percentage
PROGRESS=$((MILESTONE_SCORE * 100 / MILESTONE_TOTAL))
if [ $PROGRESS -ge 80 ]; then
    echo -e "${GREEN}🎉 Excellent progress ($PROGRESS%)${NC}"
elif [ $PROGRESS -ge 50 ]; then
    echo -e "${BLUE}🚀 Good progress ($PROGRESS%)${NC}"
elif [ $PROGRESS -ge 25 ]; then
    echo -e "${YELLOW}📈 Making progress ($PROGRESS%)${NC}"
else
    echo -e "${YELLOW}🏁 Just getting started ($PROGRESS%)${NC}"
fi

echo ""

# 7. Summary
echo -e "${BLUE}📋 Verification Summary${NC}"
echo "======================"

if [ $CHECKS_PASSED -eq $CHECKS_TOTAL ]; then
    echo -e "${GREEN}✅ All checks passed ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${GREEN}🚀 Ready to proceed with refactoring${NC}"
    exit 0
elif [ $CHECKS_PASSED -ge $((CHECKS_TOTAL * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠️  Most checks passed ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${YELLOW}⚠️  Review failing checks before proceeding${NC}"
    exit 1
else
    echo -e "${RED}❌ Multiple checks failed ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${RED}❌ Fix issues before proceeding with refactoring${NC}"
    exit 1
fi