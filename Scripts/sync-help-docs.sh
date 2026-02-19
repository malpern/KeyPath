#!/bin/zsh
# sync-help-docs.sh — LEGACY: Copy gh-pages markdown docs into the app bundle.
#
# ⚠️  DEPRECATED: The source of truth is now Sources/KeyPathAppKit/Resources/*.md
# Use Scripts/publish-help-to-web.sh to push app content → gh-pages website.
# This script is kept for reference but should not be used for normal workflow.
#
# Original purpose: website docs (gh-pages) were the canonical source, and this
# script transformed them for in-app use by:
#   1. Stripping Jekyll front matter (--- blocks)
#   2. Converting Jekyll relative_url links to in-app help: links
#   3. Converting links to website-only pages into full URLs
#
# Run from repo root: ./Scripts/sync-help-docs.sh

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
DEST="$REPO_ROOT/Sources/KeyPathAppKit/Resources"
WEBSITE="https://keypath-app.com"

# Files to sync: "source_relative_path:dest_filename"
DOCS=(
    "guides/concepts.md:concepts.md"
    "guides/use-cases.md:use-cases.md"
    "guides/home-row-mods.md:home-row-mods.md"
    "guides/tap-hold.md:tap-hold.md"
    "guides/window-management.md:window-management.md"
    "guides/action-uri.md:action-uri.md"
    "guides/privacy.md:privacy.md"
    "migration/karabiner-users.md:karabiner-users.md"
    "migration/kanata-users.md:kanata-users.md"
)

echo "=== Syncing help docs from gh-pages → app bundle ==="
echo "  Source: $GHPAGES"
echo "  Dest:   $DEST"

if [[ ! -d "$GHPAGES" ]]; then
    echo "ERROR: gh-pages worktree not found at $GHPAGES"
    echo "  Run: git worktree add .worktrees/gh-pages gh-pages"
    exit 1
fi

# Remove old standalone help files replaced by website content
for old_file in home-row-mods-guide.md advanced-hrm-techniques.md; do
    if [[ -f "$DEST/$old_file" ]]; then
        echo "  Removing old: $old_file"
        rm "$DEST/$old_file"
    fi
done

transform_file() {
    local src_path="$1"
    local dest_path="$2"

    # Read source
    local content
    content=$(<"$src_path")

    # 1. Strip Jekyll front matter (everything between first pair of ---)
    content=$(echo "$content" | awk '
        BEGIN { in_front_matter=0; done_front_matter=0 }
        /^---$/ {
            if (!done_front_matter) {
                if (!in_front_matter) { in_front_matter=1; next }
                else { in_front_matter=0; done_front_matter=1; next }
            }
        }
        { if (!in_front_matter) print }
    ')

    # 2. Convert guide links → help: links
    content=$(echo "$content" | sed -E "s#\\{\\{ *'/guides/([^']+)' *\\| *relative_url *\\}\\}#help:\\1#g")

    # 3. Convert migration links → help: links
    content=$(echo "$content" | sed -E "s#\\{\\{ *'/migration/([^']+)' *\\| *relative_url *\\}\\}#help:\\1#g")

    # 4. Convert getting-started links → website URL
    content=$(echo "$content" | sed -E "s#\\{\\{ *'/getting-started/([^']+)' *\\| *relative_url *\\}\\}#${WEBSITE}/getting-started/\\1#g")

    # 5. Convert /docs link → website URL
    content=$(echo "$content" | sed -E "s#\\{\\{ *'/docs' *\\| *relative_url *\\}\\}#${WEBSITE}/docs#g")

    # 6. Convert /faq link → website URL
    content=$(echo "$content" | sed -E "s#\\{\\{ *'/faq' *\\| *relative_url *\\}\\}#${WEBSITE}/faq#g")

    # 7. Convert any remaining relative_url patterns → website URLs
    content=$(echo "$content" | sed -E "s#\\{\\{ *'(/[^']+)' *\\| *relative_url *\\}\\}#${WEBSITE}\\1#g")

    # 8. Convert site.github_url → actual GitHub URL
    content=$(echo "$content" | sed -E "s#\\{\\{ *site\\.github_url *\\}\\}#https://github.com/malpern/KeyPath#g")

    # 9. Remove kramdown attributes like {: .no_toc}
    content=$(echo "$content" | sed -E '/^\{:.*\}$/d')

    # 10. Strip website-only HTML blocks (multi-line removal with perl)
    # Remove full div blocks: migration-hero, docs-grid, docs-card, geometric-*, geo-card
    content=$(echo "$content" | perl -0pe 's/<div class="(migration-hero|docs-grid|docs-card|geometric-section|geometric-grid|geo-card)"[^>]*>.*?<\/div>\s*//gs')
    # Remove inline style divs and their closing tags
    content=$(echo "$content" | perl -0pe 's/<div style="[^"]*">.*?<\/div>\s*//gs')
    # Remove SVG blocks
    content=$(echo "$content" | perl -0pe 's/<svg[^>]*>.*?<\/svg>//gs')
    content=$(echo "$content" | perl -0pe 's/<defs>.*?<\/defs>//gs')

    echo "$content" > "$dest_path"
}

synced=0
for entry in "${DOCS[@]}"; do
    src="${entry%%:*}"
    dest_name="${entry##*:}"
    src_path="$GHPAGES/$src"
    dest_path="$DEST/$dest_name"

    if [[ ! -f "$src_path" ]]; then
        echo "  SKIP: $src (not found)"
        continue
    fi

    echo "  Syncing: $src → $dest_name"
    transform_file "$src_path" "$dest_path"
    synced=$((synced + 1))
done

echo ""
echo "=== Done: $synced files synced ==="
echo ""
echo "Next: rebuild the app to pick up the new help content."
echo "  swift build  OR  ./Scripts/quick-deploy.sh"
