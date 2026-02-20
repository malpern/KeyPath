#!/bin/zsh
# validate-screenshot-manifest.sh
#
# Ensures screenshot manifest view names match actual Swift structs.
# Run from repo root. Exits non-zero on drift.
#
# Usage:
#   ./Scripts/validate-screenshot-manifest.sh        # validate only
#   ./Scripts/validate-screenshot-manifest.sh --fix   # regenerate manifest from tags

set -euo pipefail

RESOURCES="Sources/KeyPathAppKit/Resources"
UI_SOURCES="Sources/KeyPathAppKit/UI"
MANIFEST="docs/screenshot-manifest.yaml"

errors=0

# ---------------------------------------------------------------------------
# 1. Extract view names from <!-- screenshot: --> tags in markdown files
# ---------------------------------------------------------------------------
echo "Checking screenshot tags against Swift source..."

# Get all view names from screenshot tags (skip non-snapshot methods)
view_names=()
while IFS= read -r line; do
    method=$(echo "$line" | sed -E 's/.*method="([^"]+)".*/\1/')
    view=$(echo "$line" | sed -E 's/.*view="([^"]+)".*/\1/')
    id=$(echo "$line" | sed -E 's/.*id="([^"]+)".*/\1/')

    # Skip non-snapshot methods (peekaboo, manual)
    if [[ "$method" != "snapshot" ]]; then
        continue
    fi

    # Check that struct exists in Swift sources
    if ! grep -rq "struct ${view}:" "$UI_SOURCES" 2>/dev/null; then
        echo "  FAIL: view=\"${view}\" (id=${id}) — no 'struct ${view}' found in ${UI_SOURCES}/"
        ((errors++))
    else
        echo "  OK:   view=\"${view}\" (id=${id})"
    fi

    view_names+=("$view")
done < <(grep -rh '<!-- screenshot:' "$RESOURCES"/*.md 2>/dev/null)

echo ""
echo "Checked ${#view_names[@]} snapshot view references."

# ---------------------------------------------------------------------------
# 2. Verify manifest YAML view names match the tags
# ---------------------------------------------------------------------------
echo ""
echo "Checking manifest matches embedded tags..."

# Extract view names from manifest (only snapshot method entries)
manifest_views=()
in_snapshot=false
while IFS= read -r line; do
    if [[ "$line" =~ "method: snapshot" ]]; then
        in_snapshot=true
    elif [[ "$line" =~ "method:" ]]; then
        in_snapshot=false
    elif $in_snapshot && [[ "$line" =~ "view:" ]]; then
        manifest_view=$(echo "$line" | sed -E 's/.*view: (.*)/\1/' | tr -d ' ')
        manifest_views+=("$manifest_view")
    fi
done < "$MANIFEST"

# Extract view names from tags (snapshot only)
tag_views=()
while IFS= read -r line; do
    method=$(echo "$line" | sed -E 's/.*method="([^"]+)".*/\1/')
    view=$(echo "$line" | sed -E 's/.*view="([^"]+)".*/\1/')
    if [[ "$method" == "snapshot" ]]; then
        tag_views+=("$view")
    fi
done < <(grep -rh '<!-- screenshot:' "$RESOURCES"/*.md 2>/dev/null)

# Compare counts
if [[ ${#manifest_views[@]} -ne ${#tag_views[@]} ]]; then
    echo "  FAIL: manifest has ${#manifest_views[@]} snapshot entries, tags have ${#tag_views[@]}"
    ((errors++))
else
    echo "  OK:   manifest and tags both have ${#manifest_views[@]} snapshot entries"
fi

# Compare sorted lists
manifest_sorted=$(printf '%s\n' "${manifest_views[@]}" | sort)
tag_sorted=$(printf '%s\n' "${tag_views[@]}" | sort)

if [[ "$manifest_sorted" != "$tag_sorted" ]]; then
    echo "  FAIL: manifest view names don't match tag view names"
    echo "  Manifest only:"
    comm -23 <(echo "$manifest_sorted") <(echo "$tag_sorted") | sed 's/^/    /'
    echo "  Tags only:"
    comm -13 <(echo "$manifest_sorted") <(echo "$tag_sorted") | sed 's/^/    /'
    ((errors++))
else
    echo "  OK:   all view names match between manifest and tags"
fi

# ---------------------------------------------------------------------------
# 3. Check for renamed/deleted structs referenced in manifest mapping table
# ---------------------------------------------------------------------------
echo ""
echo "Checking View→Struct mapping table..."

# Extract struct names from the mapping table (lines between the markers)
in_table=false
while IFS= read -r line; do
    if [[ "$line" == *"VIEW → STRUCT MAPPING"* ]]; then
        in_table=true
        continue
    fi
    if $in_table && [[ "$line" == *"Snapshot test feasibility"* ]]; then
        break
    fi
    if $in_table && [[ "$line" =~ ^#[[:space:]]+[A-Z] ]]; then
        # Extract the second word (actual struct name)
        struct_name=$(echo "$line" | awk '{print $2}')
        if [[ -n "$struct_name" ]] && [[ "$struct_name" != "Actual" ]] && [[ "$struct_name" != "Manifest" ]]; then
            if ! grep -rq "struct ${struct_name}:" "$UI_SOURCES" 2>/dev/null; then
                echo "  FAIL: mapping table references '${struct_name}' — struct not found"
                ((errors++))
            else
                echo "  OK:   ${struct_name}"
            fi
        fi
    fi
done < "$MANIFEST"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
if [[ $errors -gt 0 ]]; then
    echo "FAILED: ${errors} error(s) found. Update screenshot tags and/or manifest."
    echo ""
    echo "To fix:"
    echo "  1. Rename view=\"...\" in the markdown <!-- screenshot: --> tags"
    echo "  2. Update docs/screenshot-manifest.yaml to match"
    echo "  3. Run this script again to verify"
    exit 1
else
    echo "PASSED: all screenshot view names match Swift source."
    exit 0
fi
