#!/bin/bash
# Lint check: Detect potential duplicate async calls within TaskGroups
# These can cause hangs when the called function has retry/sleep logic

set -e

echo "🔍 Checking for duplicate async calls in TaskGroups..."

# Find files with withTaskGroup and check for duplicate await calls
ISSUES=0

for file in $(grep -rl "withTaskGroup" Sources/ --include="*.swift" 2>/dev/null); do
    # Extract TaskGroup blocks and look for duplicate await patterns
    # This is a heuristic - looks for the same function called multiple times

    # Get all await calls within the file
    AWAITS=$(grep -o "await [a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*()" "$file" 2>/dev/null | sort | uniq -d)

    if [ -n "$AWAITS" ]; then
        # Check if file has TaskGroup
        if grep -q "withTaskGroup" "$file"; then
            echo "⚠️  $file may have duplicate async calls in TaskGroup:"
            echo "$AWAITS" | sed 's/^/   /'
            ISSUES=$((ISSUES + 1))
        fi
    fi
done

if [ $ISSUES -eq 0 ]; then
    echo "✅ No obvious duplicate async calls in TaskGroups found"
else
    echo ""
    echo "⚠️  Found $ISSUES file(s) with potential issues"
    echo "   Review these to ensure concurrent calls don't contend on shared resources"
fi
