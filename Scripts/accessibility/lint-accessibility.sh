#!/bin/bash
# Accessibility Modifier Linter for SwiftUI
# Detects common mistakes in accessibility modifier usage
#
# Usage: ./lint-accessibility.sh [path]
#        Default path: Sources/

set -euo pipefail

SEARCH_PATH="${1:-Sources/}"
ERRORS_FOUND=0
WARNINGS_FOUND=0

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🔍 Accessibility Modifier Linter${NC}"
echo "   Scanning: $SEARCH_PATH"
echo ""

# Function to report an error
report_error() {
    local file="$1"
    local line="$2"
    local message="$3"
    echo -e "${RED}ERROR${NC} $file:$line"
    echo "       $message"
    echo ""
    ((ERRORS_FOUND++)) || true
}

# Function to report a warning
report_warning() {
    local file="$1"
    local line="$2"
    local message="$3"
    echo -e "${YELLOW}WARNING${NC} $file:$line"
    echo "        $message"
    echo ""
    ((WARNINGS_FOUND++)) || true
}

# Check 1: Accessibility modifiers inside Button label closure
# Pattern: Button(..., label: { ... }.accessibilityIdentifier
echo -e "${CYAN}Check 1:${NC} Accessibility modifiers inside Button closures..."
while IFS=: read -r file line content; do
    if [[ -n "$file" ]]; then
        report_error "$file" "$line" \
            "Accessibility modifier appears inside Button closure. Move it after the Button."
    fi
done < <(grep -rn --include="*.swift" -E '\}[[:space:]]*\.(accessibilityIdentifier|accessibilityLabel)\(' "$SEARCH_PATH" 2>/dev/null | \
         grep -v "\.buttonStyle\|\.padding\|\.frame" || true)

# Check 2: Button with explicit label: parameter (prone to errors)
echo -e "${CYAN}Check 2:${NC} Button with explicit label: parameter..."
while IFS=: read -r file line content; do
    if [[ -n "$file" ]]; then
        # Check if accessibility is used in same file context
        if grep -q "accessibilityIdentifier\|accessibilityLabel" "$file" 2>/dev/null; then
            report_warning "$file" "$line" \
                "Consider using trailing closure syntax: Button(action:) { } instead of Button(action:, label:)"
        fi
    fi
done < <(grep -rn --include="*.swift" -E 'Button\([^)]*label:[[:space:]]*\{' "$SEARCH_PATH" 2>/dev/null || true)

# Check 3: Optional property in accessibility string interpolation
echo -e "${CYAN}Check 3:${NC} Optional properties in accessibility identifiers..."
while IFS=: read -r file line content; do
    if [[ -n "$file" ]]; then
        # Extract the variable name being accessed
        report_warning "$file" "$line" \
            "Possible optional property in accessibility modifier. Ensure property is non-optional."
    fi
done < <(grep -rn --include="*.swift" -E '\.(accessibilityIdentifier|accessibilityLabel)\("[^"]*\\?\(' "$SEARCH_PATH" 2>/dev/null | \
         grep -v "lowercased()\|uppercased()\|replacingOccurrences" || true)

# Check 4: Interactive elements without accessibility identifiers
echo -e "${CYAN}Check 4:${NC} Buttons/Toggles without accessibility identifiers..."
# Find Swift files with Button or Toggle but no accessibilityIdentifier
for file in $(find "$SEARCH_PATH" -name "*.swift" -type f 2>/dev/null); do
    if grep -q "Button\|Toggle" "$file" 2>/dev/null; then
        button_count=$(grep -c "Button\s*{\\|Button\s*(" "$file" 2>/dev/null || echo "0")
        toggle_count=$(grep -c "Toggle\s*(" "$file" 2>/dev/null || echo "0")
        id_count=$(grep -c "\.accessibilityIdentifier" "$file" 2>/dev/null || echo "0")

        interactive_count=$((button_count + toggle_count))
        if [[ $interactive_count -gt 0 && $id_count -eq 0 ]]; then
            report_warning "$file" "1" \
                "File has $interactive_count interactive elements but no accessibilityIdentifiers"
        fi
    fi
done

# Check 5: Image buttons without accessibility labels
echo -e "${CYAN}Check 5:${NC} Image-only buttons without accessibility labels..."
while IFS=: read -r file line content; do
    if [[ -n "$file" ]]; then
        # Check if there's an accessibilityLabel nearby
        nearby=$(sed -n "$((line)):$((line + 5))p" "$file" 2>/dev/null || true)
        if ! echo "$nearby" | grep -q "accessibilityLabel"; then
            report_warning "$file" "$line" \
                "Image-only button may need accessibilityLabel for VoiceOver"
        fi
    fi
done < <(grep -rn --include="*.swift" -E 'Button.*\{[[:space:]]*Image\(' "$SEARCH_PATH" 2>/dev/null || true)

# Check 6: Duplicate accessibility identifiers
echo -e "${CYAN}Check 6:${NC} Duplicate accessibility identifiers..."
# Extract all static identifier strings
grep -roh --include="*.swift" '\.accessibilityIdentifier("[^"]*")' "$SEARCH_PATH" 2>/dev/null | \
    sed 's/.*("\([^"]*\)").*/\1/' | \
    sort | uniq -d | while read -r dup; do
        if [[ -n "$dup" && ! "$dup" =~ \\ ]]; then  # Skip dynamic identifiers with interpolation
            echo -e "${YELLOW}WARNING${NC} Duplicate identifier: \"$dup\""
            grep -rn --include="*.swift" "accessibilityIdentifier(\"$dup\")" "$SEARCH_PATH" 2>/dev/null | head -3
            echo ""
            ((WARNINGS_FOUND++)) || true
        fi
    done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $ERRORS_FOUND -eq 0 && $WARNINGS_FOUND -eq 0 ]]; then
    echo -e "${GREEN}✅ No accessibility issues found!${NC}"
    exit 0
elif [[ $ERRORS_FOUND -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  $WARNINGS_FOUND warning(s) found${NC}"
    exit 0
else
    echo -e "${RED}❌ $ERRORS_FOUND error(s), $WARNINGS_FOUND warning(s) found${NC}"
    exit 1
fi
