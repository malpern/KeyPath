#!/bin/bash
# Check for missing accessibility identifiers in UI elements
# Usage: ./Scripts/check-accessibility.sh [--fix]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Patterns to find interactive UI elements
INTERACTIVE_PATTERNS=(
    "Button\s*\("
    "Toggle\s*\("
    "Picker\s*\("
)

# Files to check (Swift UI files only)
UI_FILES=$(find Sources/KeyPathAppKit/UI -name "*.swift" -type f | grep -v "/Style/" | grep -v "TitlebarHeaderAccessory.swift" | sort)

# Files that are exceptions (tests, previews, etc.)
EXCLUDED_PATTERNS=(
    "*Test*.swift"
    "*Preview*.swift"
    "*.generated.swift"
)

# Check if a file matches exclusion patterns
is_excluded() {
    local file="$1"
    for pattern in "${EXCLUDED_PATTERNS[@]}"; do
        if [[ "$file" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# Check if a Swift code block has accessibilityIdentifier
has_accessibility_identifier() {
    local code_block="$1"
    
    # Check for accessibilityIdentifier modifier
    if echo "$code_block" | grep -qE '\.accessibilityIdentifier\s*\('; then
        return 0
    fi
    
    # Check if it's a system component that doesn't need one
    if echo "$code_block" | grep -qE '(NSButton|NSToggle|NSPopUpButton|NSComboBox)'; then
        return 0  # System components use different accessibility APIs
    fi
    
    return 1
}

# Find interactive elements without accessibility identifiers
check_file() {
    local file="$1"
    local issues=0
    
    # Read file content
    local content
    content=$(cat "$file")
    
    # Check each interactive pattern
    for pattern in "${INTERACTIVE_PATTERNS[@]}"; do
        # Find all matches with context (50 lines after)
        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            
            # Check if this line contains the pattern
            if echo "$line" | grep -qE "$pattern"; then
                # Extract code block starting from this line (up to 50 lines or next closing brace)
                local start_line=$line_num
                local end_line=$((start_line + 50))
                local code_block
                code_block=$(sed -n "${start_line},${end_line}p" "$file")
                
                # Check if accessibilityIdentifier exists in this block
                if ! has_accessibility_identifier "$code_block"; then
                    echo -e "${RED}❌${NC} $file:$line_num"
                    echo -e "   Missing .accessibilityIdentifier() on: ${YELLOW}$(echo "$line" | sed 's/^[[:space:]]*//' | head -c 60)...${NC}"
                    issues=$((issues + 1))
                fi
            fi
        done <<< "$content"
    done
    
    return $issues
}

# Main execution
main() {
    echo "🔍 Checking for missing accessibility identifiers..."
    echo ""
    
    local total_issues=0
    local files_checked=0
    
    for file in $UI_FILES; do
        if is_excluded "$file"; then
            continue
        fi
        
        if [ ! -f "$file" ]; then
            continue
        fi
        
        files_checked=$((files_checked + 1))
        local issues
        issues=$(check_file "$file" || echo "0")
        total_issues=$((total_issues + issues))
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━.accessibilityIdentifier() modifier."
    echo "   See ACCESSIBILITY_COVERAGE.md for examples."
    echo ""
    
    if [ $total_issues -eq 0 ]; then
        echo -e "${GREEN}✅ All UI elements have accessibility identifiers!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Found $total_issues issue(s)${NC}"
        echo ""
        echo "💡 To fix: Add .accessibilityIdentifier(\"unique-id\") modifier to each interactive element"
        exit 1
    fi
}

main "$@"
