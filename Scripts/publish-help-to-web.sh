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
# To add a new article, add ONE line to REGISTRY below.
# The sidebar, docs index, and link map are all generated from it.
#
# Run from repo root: ./Scripts/publish-help-to-web.sh
# Then: cd .worktrees/gh-pages && git add -A && git commit && git push

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
SRC="$REPO_ROOT/Sources/KeyPathAppKit/Resources"
GHPAGES="$REPO_ROOT/.worktrees/gh-pages"
IMG_DEST="$GHPAGES/images/help"

# Accumulated orphan-screenshot reports. The transformation step
# adds an entry here every time a `<!-- screenshot: id="X" -->`
# directive references a PNG that doesn't exist in `$SRC`. We
# collect all of them across the run so the final report names
# every missing PNG at once instead of dripping them out one publish
# at a time.
MISSING_SCREENSHOT_PNGS=()

# Screenshot IDs in markdown are stable IDs; PNG filenames occasionally differ.
typeset -A SCREENSHOT_ALIASES
SCREENSHOT_ALIASES=(
    [install-auth-prompt]="permissions-login-items.png"
    [install-add-kanata-binary]="permissions-login-items.png"
    [install-accessibility-settings]="screenshot-accessibility-settings.png"
    [install-input-monitoring-done]="screenshot-input-monitoring.png"
)

# ─────────────────────────────────────────────────────────────────────
# Single document registry — ONE line per article, everything derived.
#
# Format (pipe-delimited):
#   resource_id | group | web_dir | title | nav_title | description
#
# - resource_id:  filename without .md in Sources/KeyPathAppKit/Resources/
# - group:        sidebar section (getting-started, features, reference, switching)
# - web_dir:      Jekyll output directory (getting-started, guides, migration)
# - title:        Jekyll front matter title (full)
# - nav_title:    Short sidebar/card display name
# - description:  Jekyll front matter description
#
# Order within each group determines sidebar and docs card order.
# ─────────────────────────────────────────────────────────────────────

REGISTRY=(
    # Format: resource|group|web_dir|title|nav_title|description|keywords (keywords optional)
    # Getting Started
    "installation|getting-started|getting-started|Setting Up KeyPath|Setting Up KeyPath|In two minutes your keyboard will launch apps, tile windows, and remap any key — all from the home row|install, setup, wizard, permissions, getting started, daemon, launchd"
    "concepts|getting-started|guides|Keyboard Concepts for Mac Users|Keyboard Concepts|Layers, tap-hold, modifiers, and more — explained for people who've never gone beyond System Settings|layers, tap-hold, dual-role, modifiers, kanata, keyboard basics"
    "use-cases|getting-started|guides|What You Can Build|What You Can Build|Concrete examples of what KeyPath can do — from simple remaps to full keyboard workflows|examples, workflows, ideas, inspiration, use cases"

    # Core Features
    "home-row-mods|core-features|guides|Shortcuts Without Reaching|Shortcuts Without Reaching|Turn your home row keys into modifiers — the most popular advanced keyboard technique|home row mods, HRM, CAGS, modifiers, dual-role, tap hold, ASDF JKL"
    "vim-navigation|core-features|guides|Navigate Like a Keyboard Ninja|Vim Navigation|Hold Space for hjkl arrows, copy/paste, undo, search, and line jumps — all without leaving the home row|vim, hjkl, arrows, navigation, space bar, cursor, movement"
    "leader-key|core-features|guides|Choose Your Leader Key|Leader Key|Pick which key activates all your layers — Space, Caps Lock, Tab, or Backtick. One change updates everything.|leader key, space, caps lock, tab, backtick, activator, layer trigger"
    "tap-hold|core-features|guides|One Key, Multiple Actions|One Key, Multiple Actions|Advanced key behaviors with tap-hold and tap-dance support|tap-hold, tap-dance, dual-role, hold timeout, tap-hold-release, chordal hold"
    "simple-packs|core-features|guides|Quick Tweaks|Quick Tweaks|Simple on/off packs: Escape remap, delete enhancement, backup Caps Lock, and Mission Control shortcuts|escape remap, delete enhancement, caps lock backup, mission control, simple"
    "key-repeat-control|core-features|guides|Arrow Keys at Full Speed|Fast Navigation|Arrow keys and delete repeat 3x faster while regular typing stays steady — no accidental repeats.|key repeat, fast navigation, arrow speed, repeat rate, cursor speed"

    # Feature Guides
    "numpad-layer|feature-guides|guides|A Numpad Under Your Hand|Numpad Layer|Right hand becomes a numpad, left hand gets operators. Two-step activation through the Leader key.|numpad, number pad, numbers, calculator, data entry, semicolon layer"
    "symbol-layer|feature-guides|guides|Programming Symbols Instantly|Symbol Layer|Brackets, pipes, and operators all under your home row. Three preset layouts for different coding styles.|symbol layer, brackets, braces, operators, programming, coding symbols, presets"
    "fun-layer|feature-guides|guides|F-Keys and Media Controls|Function Layer|F1-F12 on your right hand, play/pause/volume/brightness on your left. Two-step Leader activation.|function keys, F-keys, F1-F12, media, volume, brightness, play pause"
    "window-management|feature-guides|guides|Windows & App Shortcuts|Windows & App Shortcuts|App-specific keymaps and window management with KeyPath|window management, tiling, snapping, window snap, split screen, app-specific"
    "quick-launcher|feature-guides|guides|Launch Anything Instantly|Quick Launcher|Hold one key and press a letter to launch any app, URL, or folder instantly|launcher, app launcher, hyper key, quick launch, open apps"
    "action-uri|feature-guides|guides|Launching Apps & Workflows|Launching Apps|Launch apps, URLs, and folders from your keyboard with a single keystroke|action URI, deep links, keypath://, URL scheme, automation, scripts"
    "chords|feature-guides|guides|Press Two Keys at Once|Chords|Press two adjacent keys simultaneously to produce Escape, Enter, Backspace, or any other key without leaving the home row|chords, chord groups, simultaneous keys, combos, Ben Vallack"
    "auto-shift|feature-guides|guides|Symbols Without Shift|Auto-Shift Symbols|Hold a symbol key slightly longer to get the shifted version — no Shift key needed|auto-shift, shifted symbols, hold for shift, symbol shortcut"
    "alternative-layouts|feature-guides|guides|Alternative Layouts|Alternative Layouts|Colemak, Dvorak, Workman, and more — KeyPath supports 8 keymaps with a live overlay|colemak, dvorak, workman, QWERTY, keyboard layout, alternative layout"
    "keyboard-layouts|feature-guides|guides|Works With Your Keyboard|Works With Your Keyboard|15 physical keyboard layouts from MacBook to Kinesis Advantage 360|keyboard layout, MacBook, ISO, JIS, ANSI, ergonomic, split keyboard, Kinesis"
    "kindavim|feature-guides|guides|KindaVim|KindaVim|Use KindaVim for real Vim modes system-wide; KeyPath layers a live mode badge, hjkl hint overlay, and mastery insights on top|kindavim, vim modes, normal mode, visual mode, vim emulator, godbout"
    "neovim-terminal|feature-guides|guides|Neovim in the Terminal|Neovim in the Terminal|Bring Neovim navigation muscle memory to every macOS app with a Leader-layer HUD reference|neovim, terminal, vim motions, word movement, w b e"

    # Reference
    "action-uri-reference|reference|guides|Action URI Reference|Action URI Reference|Technical deep-link reference for integrating KeyPath with Raycast, Alfred, and scripts|action URI, deep link, URL scheme, keypath://, Raycast, Alfred, Shortcuts"
    "privacy|reference|guides|Privacy & Permissions|Privacy & Permissions|Exactly what KeyPath accesses on your Mac, why, and what it does with your data|privacy, permissions, input monitoring, accessibility, security, data"

    # Switching Tools
    "karabiner-users|switching|migration|Switching from Karabiner-Elements|From Karabiner-Elements|A practical guide for Karabiner-Elements users migrating to KeyPath|karabiner, karabiner-elements, migration, switching, complex modifications"
    "kanata-users|switching|migration|Tips for Existing Kanata Users|From Kanata|Use your existing Kanata config.kbd in KeyPath|kanata, config.kbd, defcfg, deflayer, migration, switching"
)

# ─────────────────────────────────────────────────────────────────────
# Group metadata — sidebar headings and docs landing page descriptions
# ─────────────────────────────────────────────────────────────────────

typeset -a GROUP_ORDER
GROUP_ORDER=(getting-started core-features feature-guides reference switching)

typeset -A GROUP_TITLES
GROUP_TITLES=(
    [getting-started]="Getting Started"
    [core-features]="Core Features"
    [feature-guides]="Feature Guides"
    [reference]="Reference"
    [switching]="Switching Tools"
)

typeset -A GROUP_CARD_TITLES
GROUP_CARD_TITLES=(
    [getting-started]="Getting Started"
    [core-features]="Core Features"
    [feature-guides]="Feature Guides"
    [reference]="Reference"
    [switching]="Switching Tools"
)

typeset -A GROUP_DESCRIPTIONS
GROUP_DESCRIPTIONS=(
    [getting-started]="Install KeyPath and get your keyboard remapping in two minutes flat."
    [core-features]="The essential features most people start with — home row mods, navigation layers, tap-hold, and quick tweaks."
    [feature-guides]="Deep dives on every KeyPath feature — layer packs, app launching, window tiling, chords, and more."
    [reference]="Technical references, privacy details, and troubleshooting."
    [switching]="Coming from Karabiner-Elements, Kanata, or another remapper? We've got migration guides for you."
)

# ─────────────────────────────────────────────────────────────────────
# Parse REGISTRY into working data structures
# ─────────────────────────────────────────────────────────────────────

# DOCS[resource] = "web_dir/resource.md:title:description:permalink"
typeset -A DOCS
# LINK_MAP[resource] = "/web_dir/resource/"
typeset -A LINK_MAP
# NAV_TITLES[resource] = "nav_title"
typeset -A NAV_TITLES
# GROUP_ITEMS[group] = "resource1 resource2 ..."  (space-separated, preserves order)
typeset -A GROUP_ITEMS
# GROUPS[resource] = "group-id"
typeset -A GROUPS
# KEYWORDS[resource] = "keyword1, keyword2, ..."
typeset -A KEYWORDS

for entry in "${REGISTRY[@]}"; do
    local id="${entry%%|*}";       local rest="${entry#*|}"
    local group="${rest%%|*}";     rest="${rest#*|}"
    local web_dir="${rest%%|*}";   rest="${rest#*|}"
    local title="${rest%%|*}";     rest="${rest#*|}"
    local nav_title="${rest%%|*}"; rest="${rest#*|}"
    # Split remaining into description and optional keywords (7th field)
    local description="${rest%%|*}"
    local keywords=""
    if [[ "$rest" == *"|"* ]]; then
        keywords="${rest#*|}"
    fi

    DOCS[$id]="${web_dir}/${id}.md:${title}:${description}:/${web_dir}/${id}/"
    LINK_MAP[$id]="/${web_dir}/${id}/"
    NAV_TITLES[$id]="$nav_title"
    GROUP_ITEMS[$group]="${GROUP_ITEMS[$group]:+${GROUP_ITEMS[$group]} }${id}"
    GROUPS[$id]="$group"
    KEYWORDS[$id]="$keywords"
done

echo "=== Publishing help docs: app → gh-pages website ==="
echo "  Source: $SRC"
echo "  Dest:   $GHPAGES"
echo "  Articles: ${#REGISTRY[@]}"

if [[ ! -d "$GHPAGES" ]]; then
    echo "ERROR: gh-pages worktree not found at $GHPAGES"
    echo "  Run: git worktree add .worktrees/gh-pages gh-pages"
    exit 1
fi

# Ensure parity with app help registry by clearing managed output files first.
# This removes stale web-only pages left from older publishing flows.
cleanup_managed_docs() {
    for dir in getting-started guides migration; do
        if [[ -d "$GHPAGES/$dir" ]]; then
            rm -f "$GHPAGES/$dir"/*.md
        else
            mkdir -p "$GHPAGES/$dir"
        fi
    done
}

generate_legacy_redirects() {
    cat > "$GHPAGES/getting-started/first-mapping.md" << 'EOF'
---
layout: default
title: First Mapping
description: Legacy redirect
permalink: /getting-started/first-mapping/
hide_sidebar: true
theme: parchment
---

<meta http-equiv="refresh" content="0; url={{ '/getting-started/installation/' | relative_url }}">
<link rel="canonical" href="{{ '/getting-started/installation/' | relative_url }}">
<p>This page moved to <a href="{{ '/getting-started/installation/' | relative_url }}">Setting Up KeyPath</a>.</p>
EOF

    cat > "$GHPAGES/guides/activity-insights.md" << 'EOF'
---
layout: default
title: Activity Insights
description: Legacy redirect
permalink: /guides/activity-insights/
hide_sidebar: true
theme: parchment
---

<meta http-equiv="refresh" content="0; url={{ '/guides/use-cases/' | relative_url }}">
<link rel="canonical" href="{{ '/guides/use-cases/' | relative_url }}">
<p>This page moved to <a href="{{ '/guides/use-cases/' | relative_url }}">What You Can Build</a>.</p>
EOF

    echo "  Generated: legacy redirects (first-mapping, activity-insights)"
}

# ─────────────────────────────────────────────────────────────────────
# Transform a single markdown file from app format to Jekyll format
# ─────────────────────────────────────────────────────────────────────

transform_file() {
    local resource="$1"
    local src_path="$SRC/${resource}.md"
    local entry="${DOCS[$resource]}"

    # Parse entry: "web_path:title:description:permalink"
    local web_path="${entry%%:*}"
    local rest="${entry#*:}"
    local title="${rest%%:*}"
    rest="${rest#*:}"
    local permalink="${rest##*:}"
    local description="${rest%:*}"
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
    content=$(echo "$content" | sed '1{/^!\[[^]]*\](header-.*\.png)$/d;}')

    # 2. Convert <!-- screenshot: id="foo" ... --> metadata into inline images
    #    so website article bodies include the same screenshots as app help.
    local converted_content=""
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        local sid=""
        sid=$(echo "$line" | sed -nE 's/^<!-- screenshot:.*id="([^"]+)".*-->$/\1/p')
        if [[ -n "$sid" ]]; then
            local file="${sid}.png"
            if [[ -n "${SCREENSHOT_ALIASES[$sid]:-}" ]]; then
                file="${SCREENSHOT_ALIASES[$sid]}"
            fi
            if [[ -f "$SRC/$file" ]]; then
                converted_content+=$'\n'"![Screenshot]({{ '/images/help/${file}' | relative_url }})"$'\n'
            else
                # Record the orphan and keep going so we can report
                # *every* missing PNG in one batch at the end of the
                # run rather than dripping them out across multiple
                # publish attempts. The reference is still skipped
                # in the output (otherwise the rendered site would
                # show a broken image link).
                MISSING_SCREENSHOT_PNGS+=("${resource}.md → screenshot id='${sid}' (expected: ${file})")
            fi
        else
            converted_content+="${line}"$'\n'
        fi
    done <<< "$content"
    content="${converted_content%$'\n'}"

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
                    "({{ \x27\/guides\/${r}\/\x27 | relative_url }}${a})";
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
permalink: ${permalink}"
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
    for img in "$SRC"/*.png; do
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
    if [[ ! -f "$css_src" ]]; then
        echo "  WARNING: help-theme.css not found at $css_src"
        return
    fi
    mkdir -p "$(dirname "$css_dest")"
    # Check for drift before copying
    if [[ -f "$css_dest" ]] && ! diff -q "$css_src" "$css_dest" > /dev/null 2>&1; then
        echo "  ⚠️  help-theme.css had drifted — overwriting website copy with app source of truth"
    fi
    cp "$css_src" "$css_dest"
    echo "  Copied: help-theme.css → assets/css/help-theme.css"
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
  <img class="docs-hero-banner" src="{{ '/images/help/header-banner.png' | relative_url }}" alt="">
  <div class="docs-hero-content">
    <h1>KeyPath Documentation</h1>
    <p class="docs-hero-subtitle">Everything you need to master keyboard remapping on your Mac</p>
    <div class="docs-hero-cta">
      <a href="{{ '/guides/concepts/' | relative_url }}" class="docs-cta-primary">New here? Start with Keyboard Concepts</a>
      <a href="{{ '/getting-started/installation/' | relative_url }}" class="docs-cta-secondary">Jump to Installation</a>
    </div>
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

    # Developer documentation section (separate from user-facing docs)
    cat >> "$out" << 'DEVDOCS'

<hr class="docs-divider">

<h2 class="docs-section-heading">Developer Documentation</h2>
<p class="docs-section-subtitle">Contributing to KeyPath or building integrations? These interactive architecture guides cover the internals.</p>

<div class="docs-grid">

<div class="docs-card">
<h3><a href="{{ '/architecture/' | relative_url }}">Architecture Guides</a></h3>
<p>Interactive visual walkthroughs of KeyPath's internal systems, data flows, and design decisions.</p>
<ul class="docs-card-links">
<li><a href="{{ '/architecture/wizard-architecture.html' | relative_url }}">Installation Wizard</a></li>
<li><a href="{{ '/architecture/overlay-architecture.html' | relative_url }}">Live Keyboard Overlay</a></li>
<li><a href="{{ '/architecture/runtime-architecture.html' | relative_url }}">Runtime & Service Lifecycle</a></li>
<li><a href="{{ '/architecture/permissions-architecture.html' | relative_url }}">PermissionOracle</a></li>
<li><a href="{{ '/architecture/rules-architecture.html' | relative_url }}">Rule Collections & Config</a></li>
<li><a href="{{ '/architecture/xpc-architecture.html' | relative_url }}">Privileged Helper & XPC</a></li>
<li><a href="{{ '/architecture/layouts-architecture.html' | relative_url }}">Keyboard Layouts</a></li>
<li><a href="{{ '/architecture/kindavim-architecture.html' | relative_url }}">KindaVim Integration</a></li>
</ul>
</div>

</div>
DEVDOCS

    echo "  Generated: docs.md"
}

# ─────────────────────────────────────────────────────────────────────
# Generate search index: search-index.json
# ─────────────────────────────────────────────────────────────────────

generate_search_index() {
    local out="$GHPAGES/search-index.json"
    echo -n '[' > "$out"
    local first=true

    for resource in "${(@k)DOCS}"; do
        local src_path="$SRC/${resource}.md"
        [[ ! -f "$src_path" ]] && continue

        local entry="${DOCS[$resource]}"
        local web_path="${entry%%:*}"
        local rest="${entry#*:}"
        local title="${rest%%:*}"
        rest="${rest#*:}"
        local description="${rest%%:*}"
        rest="${rest#*:}"
        local url="${rest%%:*}"

        local group_id="${GROUPS[$resource]}"
        local group_title="${GROUP_TITLES[$group_id]:-$group_id}"
        local manual_keywords="${KEYWORDS[$resource]}"

        # Auto-extract headings (H1-H3) as high-value search terms
        local headings
        headings=$(LC_ALL=C grep -E '^#{1,3} ' "$src_path" | \
                   LC_ALL=C sed 's/^#* *//' | \
                   tr '\n' ', ' | \
                   sed 's/, $//')

        # Combine manual keywords + auto-extracted headings
        local all_keywords=""
        if [[ -n "$manual_keywords" && -n "$headings" ]]; then
            all_keywords="${manual_keywords}, ${headings}"
        elif [[ -n "$manual_keywords" ]]; then
            all_keywords="$manual_keywords"
        else
            all_keywords="$headings"
        fi

        # Read body, strip markdown formatting and header image line.
        # Use LC_ALL=C to avoid "illegal byte sequence" on macOS.
        local body
        body=$(LC_ALL=C sed '1{/^!\[[^]]*\](header-.*\.png)$/d;}' "$src_path" | \
               LC_ALL=C sed 's/^#* *//' | \
               LC_ALL=C sed 's/!\[[^]]*\]([^)]*)//g' | \
               LC_ALL=C sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' | \
               tr '\n' ' ' | \
               LC_ALL=C sed -E 's/[[:space:]]+/ /g' | \
               cut -c 1-2000)

        # JSON-escape: backslash, double-quote, control chars
        title=$(printf '%s' "$title" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
        description=$(printf '%s' "$description" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
        group_title=$(printf '%s' "$group_title" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
        all_keywords=$(printf '%s' "$all_keywords" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
        body=$(printf '%s' "$body" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo -n ',' >> "$out"
        fi

        cat >> "$out" << ENTRY
{"title":"${title}","description":"${description}","group":"${group_title}","url":"${url}","keywords":"${all_keywords}","body":"${body}"}
ENTRY
    done

    echo ']' >> "$out"
    echo "  Generated: search-index.json"
}

# ─────────────────────────────────────────────────────────────────────
# Main: transform all registered documents, copy images, generate nav
# ─────────────────────────────────────────────────────────────────────

synced=0
skipped=0
cleanup_managed_docs
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

# Surface any screenshot directives whose PNGs are missing. We
# deliberately collect all offenders during transformation rather
# than failing at the first one — that way one publish attempt
# names every gap at once. Loud, structured failure beats the old
# silent-drop behaviour, which trickled missing references into
# the count-parity check downstream as cryptic "src=N web=N-1"
# errors.
if [[ ${#MISSING_SCREENSHOT_PNGS[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: ${#MISSING_SCREENSHOT_PNGS[@]} screenshot directive(s) reference missing PNG(s)."
    echo "Each entry below is an in-app markdown directive whose corresponding"
    echo "PNG was not found in $SRC."
    for entry in "${MISSING_SCREENSHOT_PNGS[@]}"; do
        echo "  - $entry"
    done
    echo ""
    echo "To fix:"
    echo "  - Run \`Scripts/regenerate-screenshots.sh\` to produce the missing PNGs, OR"
    echo "  - Comment out the corresponding \`<!-- screenshot: -->\` directive in source"
    echo "    until the PNG can be generated (and update docs/screenshot-manifest.yaml"
    echo "    to keep tag/manifest counts in sync)."
    exit 1
fi

echo ""
echo "--- Generating navigation ---"
generate_sidebar
generate_docs_index
generate_legacy_redirects
generate_search_index

echo ""
echo "=== Done: $synced docs published, $skipped skipped ==="
echo ""
echo "Next steps:"
echo "  cd .worktrees/gh-pages"
echo "  git add -A"
echo "  git diff --cached --stat"
echo "  git commit -m 'Sync help docs from app'"
echo "  git push origin gh-pages"
