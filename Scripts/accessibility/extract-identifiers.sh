#!/bin/bash
# Accessibility Identifier Extractor
# Extracts all accessibilityIdentifier values from SwiftUI code
# Generates a manifest for XCUITest reference
#
# Usage: ./extract-identifiers.sh [path] [--json|--swift|--markdown]
#        Default: Sources/ --markdown

set -euo pipefail

SEARCH_PATH="${1:-Sources/}"
OUTPUT_FORMAT="${2:---markdown}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

# Temporary files
STATIC_IDS=$(mktemp)
DYNAMIC_IDS=$(mktemp)
trap 'rm -f "$STATIC_IDS" "$DYNAMIC_IDS"' EXIT

echo -e "${CYAN}📋 Extracting Accessibility Identifiers${NC}" >&2
echo "   Scanning: $SEARCH_PATH" >&2
echo "" >&2

# Extract static identifiers (no interpolation)
grep -roh --include="*.swift" '\.accessibilityIdentifier("[^"\\]*")' "$SEARCH_PATH" 2>/dev/null | \
    sed 's/.*("\([^"]*\)").*/\1/' | \
    sort -u > "$STATIC_IDS"

# Extract dynamic identifiers (with interpolation patterns)
grep -roh --include="*.swift" '\.accessibilityIdentifier("[^"]*\\([^)]*)[^"]*")' "$SEARCH_PATH" 2>/dev/null | \
    sed 's/.*("\([^"]*\)").*/\1/' | \
    sort -u > "$DYNAMIC_IDS"

STATIC_COUNT=$(wc -l < "$STATIC_IDS" | tr -d ' ')
DYNAMIC_COUNT=$(wc -l < "$DYNAMIC_IDS" | tr -d ' ')

echo -e "${GREEN}Found: $STATIC_COUNT static, $DYNAMIC_COUNT dynamic identifiers${NC}" >&2
echo "" >&2

case "$OUTPUT_FORMAT" in
    --json)
        echo "{"
        echo '  "generated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",'
        echo '  "source_path": "'"$SEARCH_PATH"'",'
        echo '  "static_identifiers": ['
        first=true
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                if $first; then first=false; else echo ","; fi
                printf '    "%s"' "$id"
            fi
        done < "$STATIC_IDS"
        echo ""
        echo "  ],"
        echo '  "dynamic_patterns": ['
        first=true
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                if $first; then first=false; else echo ","; fi
                printf '    "%s"' "$id"
            fi
        done < "$DYNAMIC_IDS"
        echo ""
        echo "  ]"
        echo "}"
        ;;

    --swift)
        echo "// Auto-generated Accessibility Identifiers"
        echo "// Generated: $(date)"
        echo "// Source: $SEARCH_PATH"
        echo ""
        echo "import Foundation"
        echo ""
        echo "/// Static accessibility identifiers for XCUITest"
        echo "enum AccessibilityIdentifiers {"
        echo ""

        # Group by prefix
        current_prefix=""
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                # Extract prefix (first segment before -)
                prefix=$(echo "$id" | cut -d'-' -f1)
                if [[ "$prefix" != "$current_prefix" ]]; then
                    if [[ -n "$current_prefix" ]]; then
                        echo "    }"
                        echo ""
                    fi
                    echo "    enum ${prefix^} {"
                    current_prefix="$prefix"
                fi
                # Convert to camelCase constant name
                const_name=$(echo "$id" | sed 's/-\([a-z]\)/\U\1/g' | sed 's/^./\L&/')
                echo "        static let $const_name = \"$id\""
            fi
        done < "$STATIC_IDS"
        if [[ -n "$current_prefix" ]]; then
            echo "    }"
        fi

        echo ""
        echo "    /// Dynamic identifier patterns (use String interpolation)"
        echo "    enum Patterns {"
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                # Create pattern description
                pattern_name=$(echo "$id" | sed 's/\\([^)]*)/ID/g' | sed 's/-\([a-z]\)/\U\1/g' | sed 's/^./\L&/')
                echo "        /// Pattern: $id"
                echo "        static func $pattern_name(_ id: String) -> String {"
                # Extract the base pattern
                base=$(echo "$id" | sed 's/\\([^)]*)/{ID}/g')
                echo "            \"$base\".replacingOccurrences(of: \"{ID}\", with: id)"
                echo "        }"
            fi
        done < "$DYNAMIC_IDS"
        echo "    }"
        echo "}"
        ;;

    --markdown|*)
        echo "# Accessibility Identifiers"
        echo ""
        echo "_Generated: $(date)_"
        echo "_Source: ${SEARCH_PATH}_"
        echo ""
        echo "## Static Identifiers ($STATIC_COUNT)"
        echo ""
        echo "| Identifier | Screen | Component |"
        echo "|------------|--------|-----------|"
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                # Parse screen-component pattern
                screen=$(echo "$id" | cut -d'-' -f1)
                rest=$(echo "$id" | cut -d'-' -f2-)
                echo "| \`$id\` | $screen | $rest |"
            fi
        done < "$STATIC_IDS"
        echo ""
        echo "## Dynamic Patterns ($DYNAMIC_COUNT)"
        echo ""
        echo "| Pattern | Description |"
        echo "|---------|-------------|"
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                desc=$(echo "$id" | sed 's/\\([^)]*)/`{dynamic}`/g')
                echo "| \`$id\` | $desc |"
            fi
        done < "$DYNAMIC_IDS"
        echo ""
        echo "## Usage in XCUITest"
        echo ""
        echo "\`\`\`swift"
        echo "// Static identifier"
        echo "let button = app.buttons[\"settings-save-button\"]"
        echo ""
        echo "// Dynamic identifier"
        echo "let row = app.cells[\"rule-row-\\(ruleId)\"]"
        echo "\`\`\`"
        ;;
esac
