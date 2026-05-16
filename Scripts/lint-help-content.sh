#!/usr/bin/env bash
# lint-help-content.sh — Validate help content markdown files
# Run from the repo root: ./Scripts/lint-help-content.sh

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────────────────────────────────────────────────
# Paths (relative to repo root)
# ─────────────────────────────────────────────────────────────────────
RESOURCES="Sources/KeyPathAppKit/Resources"
HELP_BROWSER="Sources/KeyPathAppKit/UI/Help/HelpBrowserView.swift"
PUBLISH_SCRIPT="Scripts/publish-help-to-web.sh"

errors=0
warnings=0

error() {
    printf "${RED}ERROR${RESET}: %s\n" "$1"
    errors=$((errors + 1))
}

warn() {
    printf "${YELLOW}WARN${RESET}:  %s\n" "$1"
    warnings=$((warnings + 1))
}

pass() {
    printf "${GREEN}PASS${RESET}:  %s\n" "$1"
}

# ─────────────────────────────────────────────────────────────────────
# Collect article files (exclude .prompt.md and Sounds/README.md)
# ─────────────────────────────────────────────────────────────────────
mapfile -t ARTICLES < <(find "$RESOURCES" -maxdepth 1 -name '*.md' \
    ! -name '*.prompt.md' \
    ! -name 'README.md' \
    -type f | sort)

if [[ ${#ARTICLES[@]} -eq 0 ]]; then
    error "No article .md files found in $RESOURCES"
    exit 1
fi

echo ""
printf "${BOLD}Linting %d help articles in %s${RESET}\n\n" "${#ARTICLES[@]}" "$RESOURCES"

# ─────────────────────────────────────────────────────────────────────
# 1. help: link validation
# ─────────────────────────────────────────────────────────────────────
echo "── 1. help: link validation ──"
check1_pass=true
for file in "${ARTICLES[@]}"; do
    # Extract all help:xxx targets (macOS compatible)
    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        if [[ ! -f "$RESOURCES/$target.md" ]]; then
            error "$(basename "$file"): broken link help:$target (no $target.md found)"
            check1_pass=false
        fi
    done < <(grep -oE 'help:[a-zA-Z0-9_-]+' "$file" 2>/dev/null | sed 's/^help://' | sort -u)
done
[[ "$check1_pass" == true ]] && pass "All help: links resolve"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 2. Back to Docs
# ─────────────────────────────────────────────────────────────────────
echo "── 2. Back to Docs ──"
check2_pass=true
for file in "${ARTICLES[@]}"; do
    if ! grep -q '\[Back to Docs\]' "$file"; then
        error "$(basename "$file"): missing [Back to Docs] link"
        check2_pass=false
    fi
done
[[ "$check2_pass" == true ]] && pass "All articles contain [Back to Docs]"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 3. Header image
# ─────────────────────────────────────────────────────────────────────
echo "── 3. Header image ──"
check3_pass=true
for file in "${ARTICLES[@]}"; do
    first_line=$(head -1 "$file")
    # Check format: ![...](header-*.png)
    header_re='^\!\[.*\]\(header-[^)]+\.png\)$'
    if [[ ! "$first_line" =~ $header_re ]]; then
        error "$(basename "$file"): first line is not a header image (got: $first_line)"
        check3_pass=false
    else
        # Extract the PNG filename using sed
        png=$(echo "$first_line" | sed -n 's/.*(\(header-[^)]*\.png\)).*/\1/p')
        if [[ -n "$png" && ! -f "$RESOURCES/$png" ]]; then
            error "$(basename "$file"): header image $png does not exist"
            check3_pass=false
        fi
    fi
done
[[ "$check3_pass" == true ]] && pass "All articles have valid header images"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 4. Screenshot PNGs
# ─────────────────────────────────────────────────────────────────────
echo "── 4. Screenshot PNGs ──"
check4_pass=true
for file in "${ARTICLES[@]}"; do
    # Find screenshot directives, skip manual and peekaboo methods
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip if method="manual" or method="peekaboo"
        if echo "$line" | grep -qE 'method="(manual|peekaboo)"'; then
            continue
        fi
        # Extract the id using sed
        screenshot_id=$(echo "$line" | sed -n 's/.*id="\([^"]*\)".*/\1/p')
        if [[ -n "$screenshot_id" && ! -f "$RESOURCES/$screenshot_id.png" ]]; then
            error "$(basename "$file"): screenshot $screenshot_id.png missing"
            check4_pass=false
        fi
    done < <(grep '<!-- screenshot:' "$file" 2>/dev/null || true)
done
[[ "$check4_pass" == true ]] && pass "All screenshot PNGs exist (or are manual/peekaboo)"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 5. Registry parity
# ─────────────────────────────────────────────────────────────────────
echo "── 5. Registry parity ──"
check5_pass=true
for file in "${ARTICLES[@]}"; do
    basename_noext=$(basename "$file" .md)

    # Check HelpBrowserView.swift (look for resource: "xxx")
    if ! grep -q "resource: \"$basename_noext\"" "$HELP_BROWSER" 2>/dev/null; then
        error "$basename_noext.md: not registered in HelpBrowserView.swift allTopics"
        check5_pass=false
    fi

    # Check publish-help-to-web.sh (look for slug at start of REGISTRY entry)
    if ! grep -q "\"$basename_noext|" "$PUBLISH_SCRIPT" 2>/dev/null; then
        error "$basename_noext.md: not registered in publish-help-to-web.sh REGISTRY"
        check5_pass=false
    fi
done
[[ "$check5_pass" == true ]] && pass "All articles registered in HelpBrowserView and publish script"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 6. Broken external URLs
# ─────────────────────────────────────────────────────────────────────
echo "── 6. Broken external URLs ──"
check6_pass=true
for file in "${ARTICLES[@]}"; do
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        error "$(basename "$file"): known-broken URL: $match"
        check6_pass=false
    done < <(grep -oE 'https?://[^[:space:])\"]*' "$file" 2>/dev/null \
        | grep -E 'keypath-app\.com/(docs|faq|getting-started)' || true)
done
[[ "$check6_pass" == true ]] && pass "No known-broken external URLs"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 7. Consistent terminology
# ─────────────────────────────────────────────────────────────────────
echo "── 7. Consistent terminology ──"
check7_pass=true

# Known-wrong patterns → correct versions
declare -a WRONG_TERMS=(
    "Run Setup Wizard|Install wizard..."
    "macOS 14 (Sonoma)|macOS 15 (Sequoia)"
    "separate companion app|built-in plugin"
)

for entry in "${WRONG_TERMS[@]}"; do
    wrong="${entry%%|*}"
    right="${entry##*|}"
    for file in "${ARTICLES[@]}"; do
        if grep -q "$wrong" "$file" 2>/dev/null; then
            error "$(basename "$file"): contains '$wrong' — should be '$right'"
            check7_pass=false
        fi
    done
done

# Check macOS version matches Package.swift deployment target
PACKAGE_SWIFT="Package.swift"
if [[ -f "$PACKAGE_SWIFT" ]]; then
    deploy_target=$(grep -oE '\.macOS\(\.v[0-9]+\)' "$PACKAGE_SWIFT" | head -1 | grep -oE '[0-9]+')
    if [[ -n "$deploy_target" ]]; then
        for file in "${ARTICLES[@]}"; do
            # Look for "macOS NN" where NN doesn't match the deployment target
            while IFS= read -r match; do
                [[ -z "$match" ]] && continue
                found_ver=$(echo "$match" | grep -oE 'macOS [0-9]+' | grep -oE '[0-9]+')
                if [[ -n "$found_ver" && "$found_ver" != "$deploy_target" ]]; then
                    error "$(basename "$file"): references macOS $found_ver but Package.swift targets macOS $deploy_target"
                    check7_pass=false
                fi
            done < <(grep -oE 'macOS [0-9]+ \([A-Z][a-z]+\)' "$file" 2>/dev/null || true)
        done
    fi
fi

[[ "$check7_pass" == true ]] && pass "No known-wrong terminology"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 8. Orphan check (informational)
# ─────────────────────────────────────────────────────────────────────
echo "── 8. Orphan header images ──"
check8_pass=true
while IFS= read -r png; do
    [[ -z "$png" ]] && continue
    png_name=$(basename "$png")
    # Check if any .md file references this PNG
    if ! grep -rlq "$png_name" "$RESOURCES"/*.md 2>/dev/null; then
        warn "Orphan header image: $png_name (not referenced by any .md)"
        check8_pass=false
    fi
done < <(find "$RESOURCES" -maxdepth 1 -name 'header-*.png' -type f | sort)
[[ "$check8_pass" == true ]] && pass "No orphan header images"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
    printf "${GREEN}${BOLD}All checks passed!${RESET}\n"
elif [[ $errors -eq 0 ]]; then
    printf "${YELLOW}${BOLD}Passed with %d warning(s)${RESET}\n" "$warnings"
else
    printf "${RED}${BOLD}Failed: %d error(s), %d warning(s)${RESET}\n" "$errors" "$warnings"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $errors -eq 0 ]] && exit 0 || exit 1
