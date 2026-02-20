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
#   6. Generating sidebar navigation (_includes/sidebar.html)
#   7. Generating docs landing page (docs.md)
#
# To add a new article:
#   1. Add it to DOCS (content transform)
#   2. Add it to LINK_MAP (link resolution)
#   3. Add it to NAV_TITLES (sidebar/card display name)
#   4. Add its resource ID to the appropriate group in GROUP_ITEMS
#   That's it — sidebar and docs index are generated automatically.
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

# ─────────────────────────────────────────────────────────────────────
# Navigation registry — drives sidebar.html and docs.md generation
#
# NAV_TITLES: short display names for sidebar and docs card links
# GROUP_ORDER: section display order
# GROUP_ITEMS: resource IDs per group, space-separated, in display order
# GROUP_TITLES: section headings for sidebar
# GROUP_CARD_TITLES: section headings for docs landing cards
# GROUP_DESCRIPTIONS: card body text on docs landing page
# ─────────────────────────────────────────────────────────────────────

typeset -A NAV_TITLES
NAV_TITLES=(
    [installation]="Setting Up KeyPath"
    [concepts]="Keyboard Concepts"
    [use-cases]="What You Can Build"
    [home-row-mods]="Shortcuts Without Reaching"
    [tap-hold]="One Key, Multiple Actions"
    [window-management]="Windows & App Shortcuts"
    [action-uri]="Launching Apps"
    [alternative-layouts]="Alternative Layouts"
    [keyboard-layouts]="Works With Your Keyboard"
    [action-uri-reference]="Action URI Reference"
    [privacy]="Privacy & Permissions"
    [karabiner-users]="From Karabiner-Elements"
    [kanata-users]="From Kanata"
)

typeset -a GROUP_ORDER
GROUP_ORDER=(getting-started features reference switching)

typeset -A GROUP_ITEMS
GROUP_ITEMS=(
    [getting-started]="installation concepts use-cases"
    [features]="home-row-mods tap-hold window-management action-uri alternative-layouts keyboard-layouts"
    [reference]="action-uri-reference privacy"
    [switching]="karabiner-users kanata-users"
)

typeset -A GROUP_TITLES
GROUP_TITLES=(
    [getting-started]="Getting Started"
    [features]="Features"
    [reference]="Reference"
    [switching]="Switching Tools"
)

typeset -A GROUP_CARD_TITLES
GROUP_CARD_TITLES=(
    [getting-started]="Getting Started"
    [features]="Features"
    [reference]="Reference"
    [switching]="Switching Tools?"
)

typeset -A GROUP_DESCRIPTIONS
GROUP_DESCRIPTIONS=(
    [getting-started]="Install KeyPath and get your keyboard remapping in two minutes flat."
    [features]="Deep dives on every KeyPath feature — home row mods, tap-hold, app launching, window tiling, and more."
    [reference]="Technical references, privacy details, and troubleshooting."
    [switching]="Coming from Karabiner-Elements, Kanata, or another remapper? We've got migration guides for you."
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

    # 1. Extract header image filename (line 1: ![Alt](header-*.png)) for front matter,
    #    then strip the line from the content body.
    local header_image=""
    local first_line=$(echo "$content" | head -1)
    if [[ "$first_line" == '!'*'](header-'*'.png)' ]]; then
        header_image=$(echo "$first_line" | sed -E 's/^!\[[^]]*\]\((header-[^)]+\.png)\)$/\1/')
    fi
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

    # 5. Build front matter (with parchment theme and optional header image)
    local front_matter="---
layout: default
title: \"${title}\"
description: \"${description}\"
theme: parchment"
    if [[ -n "$header_image" ]]; then
        front_matter="${front_matter}
header_image: ${header_image}"
    fi
    front_matter="${front_matter}
---"

    # 6. Write output
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
# Copy help-theme.css to gh-pages assets
# ─────────────────────────────────────────────────────────────────────

copy_theme_css() {
    local css_src="$SRC/help-theme.css"
    local css_dest="$GHPAGES/assets/css/help-theme.css"
    if [[ -f "$css_src" ]]; then
        mkdir -p "$(dirname "$css_dest")"
        cp "$css_src" "$css_dest"
        echo "  Copied: help-theme.css → assets/css/help-theme.css"
    else
        echo "  WARNING: help-theme.css not found at $css_src"
    fi
}

# ─────────────────────────────────────────────────────────────────────
# Generate sidebar navigation: _includes/sidebar.html
# ─────────────────────────────────────────────────────────────────────

generate_sidebar() {
    local out="$GHPAGES/_includes/sidebar.html"
    mkdir -p "$(dirname "$out")"

    # Start nav
    echo '<nav class="sidebar-nav">' > "$out"
    echo '    <ul class="nav-tree">' >> "$out"

    for group in "${GROUP_ORDER[@]}"; do
        local title="${GROUP_TITLES[$group]}"
        local items=(${=GROUP_ITEMS[$group]})

        echo "        <!-- ${title} -->" >> "$out"
        echo '        <li class="nav-section">' >> "$out"
        echo "            <div class=\"nav-section-title\">${title}</div>" >> "$out"
        echo '            <ul class="nav-section-items">' >> "$out"

        for item in "${items[@]}"; do
            local url_path="${LINK_MAP[$item]}"
            local nav_title="${NAV_TITLES[$item]}"
            echo "                <li class=\"nav-item {% if page.url contains '${url_path}' %}active{% endif %}\">" >> "$out"
            echo "                    <a href=\"{{ '${url_path}' | relative_url }}\" class=\"nav-link\">${nav_title}</a>" >> "$out"
            echo '                </li>' >> "$out"
        done

        echo '            </ul>' >> "$out"
        echo '        </li>' >> "$out"
        echo '' >> "$out"
    done

    echo '    </ul>' >> "$out"
    echo '</nav>' >> "$out"

    echo "  Generated: _includes/sidebar.html"
}

# ─────────────────────────────────────────────────────────────────────
# Generate docs landing page: docs.md
# ─────────────────────────────────────────────────────────────────────

generate_docs_index() {
    local out="$GHPAGES/docs.md"

    # Static hero section (always links to concepts + installation)
    cat > "$out" << 'HERO'
---
layout: default
title: Documentation
description: Guides and references for KeyPath keyboard remapping on macOS
hide_sidebar: true
content_class: content-full docs-landing
permalink: /docs
theme: parchment
---

<div class="docs-hero">
  <div class="docs-hero-content">
    <h1>KeyPath Documentation</h1>
    <p class="docs-hero-subtitle">Everything you need to master keyboard remapping on your Mac</p>
    <div class="docs-hero-cta">
      <a href="{{ '/guides/concepts' | relative_url }}" class="docs-cta-primary">New here? Start with Keyboard Concepts</a>
      <a href="{{ '/getting-started/installation' | relative_url }}" class="docs-cta-secondary">Jump to Installation</a>
    </div>
  </div>
  <div class="docs-hero-visual">
    <div class="docs-hero-keyboard">
      <div class="hero-hand">
        <div class="hero-key">A<span>⇧</span></div>
        <div class="hero-key">S<span>⌃</span></div>
        <div class="hero-key">D<span>⌥</span></div>
        <div class="hero-key">F<span>⌘</span></div>
      </div>
      <div class="hero-key-gap"></div>
      <div class="hero-hand">
        <div class="hero-key">J<span>⌘</span></div>
        <div class="hero-key">K<span>⌥</span></div>
        <div class="hero-key">L<span>⌃</span></div>
        <div class="hero-key">;<span>⇧</span></div>
      </div>
    </div>
    <p class="docs-hero-caption">Tap for letters. Hold for modifiers. Your fingers never leave home.</p>
  </div>
</div>

<div class="docs-grid">
HERO

    # Generate a card for each group
    for group in "${GROUP_ORDER[@]}"; do
        local card_title="${GROUP_CARD_TITLES[$group]}"
        local description="${GROUP_DESCRIPTIONS[$group]}"
        local items=(${=GROUP_ITEMS[$group]})
        local first_item="${items[1]}"
        local first_url="${LINK_MAP[$first_item]}"

        echo '' >> "$out"
        echo '<div class="docs-card">' >> "$out"
        echo "<h3><a href=\"{{ '${first_url}' | relative_url }}\">${card_title}</a></h3>" >> "$out"
        echo "<p>${description}</p>" >> "$out"
        echo '<ul class="docs-card-links">' >> "$out"

        for item in "${items[@]}"; do
            local url_path="${LINK_MAP[$item]}"
            local nav_title="${NAV_TITLES[$item]}"
            echo "<li><a href=\"{{ '${url_path}' | relative_url }}\">${nav_title}</a></li>" >> "$out"
        done

        echo '</ul>' >> "$out"
        echo '</div>' >> "$out"
    done

    echo '' >> "$out"
    echo '</div>' >> "$out"

    echo "  Generated: docs.md"
}

# ─────────────────────────────────────────────────────────────────────
# Main: transform all registered documents, copy images, generate nav
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
copy_theme_css

echo ""
echo "--- Generating navigation ---"
generate_sidebar
generate_docs_index

echo ""
echo "=== Done: $synced docs published, $skipped skipped ==="
echo ""
echo "Next steps:"
echo "  cd .worktrees/gh-pages"
echo "  git add -A"
echo "  git diff --cached --stat"
echo "  git commit -m 'Sync help docs from app'"
echo "  git push origin gh-pages"
