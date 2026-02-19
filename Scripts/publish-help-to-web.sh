#!/bin/zsh
# publish-help-to-web.sh — Publish in-app help content to the gh-pages website.
#
# Source of truth: Sources/KeyPathAppKit/Resources/*.md (in-app help)
# Destination:     .worktrees/gh-pages/ (Jekyll website on GitHub Pages)
#
# This script transforms app-format markdown into Jekyll-compatible pages by:
#   1. Adding Jekyll front matter (layout, title, description)
#   2. Converting help: links to Jekyll {{ relative_url }} links
#   3. Converting header image references to website image paths
#   4. Stripping <!-- screenshot: --> metadata tags (app-only)
#   5. Copying images (headers, concepts, decorative) to website assets
#
# Run from repo root: ./Scripts/publish-help-to-web.sh
# Then: cd .worktrees/gh-pages && git add -A && git commit && git push

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
SRC="$REPO_ROOT/Sources/KeyPathAppKit/Resources"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
IMG_DEST="$GHPAGES/images/help"

# ─────────────────────────────────────────────────────────────────────
# Document registry: resource_name → "web_path:title:description"
#
# web_path determines the Jekyll directory (guides/, migration/, getting-started/)
# title and description become Jekyll front matter
# ─────────────────────────────────────────────────────────────────────

typeset -A DOCS
DOCS=(
    # Getting Started
    [installation]="getting-started/installation.md:Setting Up KeyPath:In two minutes your keyboard will launch apps, tile windows, and remap any key — all from the home row"
    [concepts]="guides/concepts.md:Keyboard Concepts for Mac Users:Layers, tap-hold, modifiers, and more — explained for people who've never gone beyond System Settings"
    [use-cases]="guides/use-cases.md:What You Can Build:Concrete examples of what KeyPath can do — from simple remaps to full keyboard workflows"

    # Features
    [home-row-mods]="guides/home-row-mods.md:Shortcuts Without Reaching:Turn your home row keys into modifiers — the most popular advanced keyboard technique"
    [tap-hold]="guides/tap-hold.md:One Key, Multiple Actions:Advanced key behaviors with tap-hold and tap-dance support"
    [window-management]="guides/window-management.md:Windows & App Shortcuts:App-specific keymaps and window management with KeyPath"
    [action-uri]="guides/action-uri.md:Launching Apps & Workflows:Launch apps, URLs, and folders from your keyboard with a single keystroke"
    [alternative-layouts]="guides/alternative-layouts.md:Alternative Layouts:Colemak, Dvorak, Workman, and more — KeyPath supports 8 keymaps with a live overlay"
    [keyboard-layouts]="guides/keyboard-layouts.md:Works With Your Keyboard:12 physical keyboard layouts from MacBook to Kinesis Advantage 360"

    # Reference
    [action-uri-reference]="guides/action-uri-reference.md:Action URI Reference:Technical deep-link reference for integrating KeyPath with Raycast, Alfred, and scripts"
    [privacy]="guides/privacy.md:Privacy & Permissions:Exactly what KeyPath accesses on your Mac, why, and what it does with your data"

    # Switching Tools
    [karabiner-users]="migration/karabiner-users.md:Switching from Karabiner-Elements:A practical guide for Karabiner-Elements users migrating to KeyPath"
    [kanata-users]="migration/kanata-users.md:Tips for Existing Kanata Users:Use your existing Kanata config.kbd in KeyPath"
)

# Map help: link targets to their website paths
typeset -A LINK_MAP
LINK_MAP=(
    [installation]="/getting-started/installation"
    [concepts]="/guides/concepts"
    [use-cases]="/guides/use-cases"
    [home-row-mods]="/guides/home-row-mods"
    [tap-hold]="/guides/tap-hold"
    [window-management]="/guides/window-management"
    [action-uri]="/guides/action-uri"
    [alternative-layouts]="/guides/alternative-layouts"
    [keyboard-layouts]="/guides/keyboard-layouts"
    [action-uri-reference]="/guides/action-uri-reference"
    [privacy]="/guides/privacy"
    [karabiner-users]="/migration/karabiner-users"
    [kanata-users]="/migration/kanata-users"
)

echo "=== Publishing help docs: app → gh-pages website ==="
echo "  Source: $SRC"
echo "  Dest:   $GHPAGES"

if [[ ! -d "$GHPAGES" ]]; then
    echo "ERROR: gh-pages worktree not found at $GHPAGES"
    echo "  Run: git worktree add .worktrees/gh-pages gh-pages"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# Transform a single markdown file from app format to Jekyll format
# ─────────────────────────────────────────────────────────────────────

transform_file() {
    local resource="$1"
    local src_path="$SRC/${resource}.md"
    local entry="${DOCS[$resource]}"

    # Parse entry: "web_path:title:description"
    local web_path="${entry%%:*}"
    local rest="${entry#*:}"
    local title="${rest%%:*}"
    local description="${rest#*:}"
    local dest_path="$GHPAGES/$web_path"

    # Ensure destination directory exists
    mkdir -p "$(dirname "$dest_path")"

    # Read source
    local content
    content=$(<"$src_path")

    # 1. Strip the header image line (line 1: ![Alt](header-*.png))
    #    We'll handle images separately for the website
    content=$(echo "$content" | sed '1{/^!\[.*\](header-.*\.png)$/d;}')

    # 2. Strip <!-- screenshot: --> metadata tags (app-only)
    content=$(echo "$content" | sed '/^<!-- screenshot:.*-->$/d')

    # 3. Convert inline concept images to website image paths
    #    ![Alt](concepts-foo.png) → ![Alt]({{ '/images/help/concepts-foo.png' | relative_url }})
    content=$(echo "$content" | sed -E "s#!\[([^]]*)\]\(((concepts|decor|header|permissions)-[^)]+\.png)\)#![\1]({{ '/images/help/\2' | relative_url }})#g")

    # 4. Convert help: links to Jekyll relative_url links
    #    Write link map to temp file, then use perl to do all replacements
    local tmpmap=$(mktemp)
    for link_resource link_path in "${(@kv)LINK_MAP}"; do
        echo "${link_resource}=${link_path}" >> "$tmpmap"
    done
    content=$(echo "$content" | perl -e '
        # Read link map from file
        my %map;
        open(my $fh, "<", $ARGV[0]) or die;
        while (<$fh>) { chomp; my ($k,$v) = split /=/, $_, 2; $map{$k} = $v; }
        close $fh;

        # Process stdin
        while (my $line = <STDIN>) {
            # Convert known help: links (with optional #anchor)
            $line =~ s/\(help:([a-z0-9-]+)(#[^)]+)?\)/
                my $r = $1; my $a = $2 || "";
                if (exists $map{$r}) {
                    "({{ \x27" . $map{$r} . "\x27 | relative_url }}${a})";
                } else {
                    "({{ \x27\/guides\/${r}\x27 | relative_url }}${a})";
                }
            /ge;
            print $line;
        }
    ' "$tmpmap")
    rm -f "$tmpmap"

    # 6. Build front matter
    local front_matter="---
layout: default
title: \"${title}\"
description: \"${description}\"
---"

    # 7. Write output
    echo "$front_matter" > "$dest_path"
    echo "" >> "$dest_path"
    echo "$content" >> "$dest_path"
}

# ─────────────────────────────────────────────────────────────────────
# Copy images to gh-pages
# ─────────────────────────────────────────────────────────────────────

copy_images() {
    echo ""
    echo "--- Copying images ---"
    mkdir -p "$IMG_DEST"

    local copied=0
    for img in "$SRC"/header-*.png "$SRC"/concepts-*.png "$SRC"/decor-*.png; do
        if [[ -f "$img" ]]; then
            local name=$(basename "$img")
            cp "$img" "$IMG_DEST/$name"
            echo "  Image: $name"
            copied=$((copied + 1))
        fi
    done
    echo "  $copied images copied to images/help/"
}

# ─────────────────────────────────────────────────────────────────────
# Main: transform all registered documents
# ─────────────────────────────────────────────────────────────────────

synced=0
skipped=0
for resource in "${(@k)DOCS}"; do
    src_path="$SRC/${resource}.md"
    if [[ ! -f "$src_path" ]]; then
        echo "  SKIP: ${resource}.md (not found in Resources/)"
        skipped=$((skipped + 1))
        continue
    fi

    entry="${DOCS[$resource]}"
    web_path="${entry%%:*}"
    echo "  Publishing: ${resource}.md → $web_path"
    transform_file "$resource"
    synced=$((synced + 1))
done

copy_images

echo ""
echo "=== Done: $synced docs published, $skipped skipped ==="
echo ""
echo "Next steps:"
echo "  cd .worktrees/gh-pages"
echo "  git add -A"
echo "  git diff --cached --stat"
echo "  git commit -m 'Sync help docs from app'"
echo "  git push origin gh-pages"
