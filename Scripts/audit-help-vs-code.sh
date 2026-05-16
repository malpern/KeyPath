#!/usr/bin/env bash
# audit-help-vs-code.sh — Extract feature metadata from code for AI review
#
# This script gathers facts from the codebase and compares them against help
# content. It produces a structured report that an AI agent can review to
# find mismatches between what the code does and what the docs say.
#
# Usage:
#   ./Scripts/audit-help-vs-code.sh           # Print report to stdout
#   ./Scripts/audit-help-vs-code.sh --json    # Machine-readable output
#
# Designed to be run before publishing help content. Feed the output to
# Claude Code or another AI for semantic review.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

RESOURCES="Sources/KeyPathAppKit/Resources"
SOURCES="Sources/KeyPathAppKit"

echo "═══════════════════════════════════════════════════════════════"
echo "  Help Content vs Code Audit — Feature Fingerprint Report"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ─────────────────────────────────────────────────────────────────────
# 1. Registered packs (features users can enable)
# ─────────────────────────────────────────────────────────────────────
echo "── 1. Registered Packs (from PackRegistry.swift) ──"
echo ""
grep -E 'Pack\(|id:.*"com\.keypath|displayName:' "$SOURCES/Services/Packs/PackRegistry.swift" 2>/dev/null \
    | sed 's/^[[:space:]]*//' | head -40
echo ""

# ─────────────────────────────────────────────────────────────────────
# 2. Rule collection types (from RuleCollectionCatalog)
# ─────────────────────────────────────────────────────────────────────
echo "── 2. Rule Collection Types (from catalog) ──"
echo ""
grep -E 'displayName|collectionType|category:' "$SOURCES/Services/RuleCollections/RuleCollectionCatalog.swift" 2>/dev/null \
    | sed 's/^[[:space:]]*//' | head -60
echo ""

# ─────────────────────────────────────────────────────────────────────
# 3. Menu items (what users see in the menu bar)
# ─────────────────────────────────────────────────────────────────────
echo "── 3. Menu Items (from AppMenuCommands.swift) ──"
echo ""
grep -E 'Button\("|Text\("|Label\(' "$SOURCES/Core/AppMenuCommands.swift" 2>/dev/null \
    | sed 's/^[[:space:]]*//' | head -30
echo ""

# ─────────────────────────────────────────────────────────────────────
# 4. Deployment target
# ─────────────────────────────────────────────────────────────────────
echo "── 4. Deployment Target ──"
echo ""
grep -E '\.macOS\(' Package.swift | sed 's/^[[:space:]]*//'
echo ""

# ─────────────────────────────────────────────────────────────────────
# 5. Action URI schemes (what keypath:// URLs are supported)
# ─────────────────────────────────────────────────────────────────────
echo "── 5. Action URI Schemes ──"
echo ""
grep -rE '"keypath://' "$SOURCES" --include="*.swift" 2>/dev/null \
    | grep -v ".build" | sed 's/^[[:space:]]*//' | head -20
echo ""

# ─────────────────────────────────────────────────────────────────────
# 6. Physical layouts (keyboards supported)
# ─────────────────────────────────────────────────────────────────────
echo "── 6. Physical Layouts ──"
echo ""
grep -E 'static.*:.*PhysicalLayout|id:.*"[a-z]' "$SOURCES/Models/PhysicalLayout+Builtins.swift" 2>/dev/null \
    | sed 's/^[[:space:]]*//' | head -30
echo ""

# ─────────────────────────────────────────────────────────────────────
# 7. Logical keymaps (alternative layouts)
# ─────────────────────────────────────────────────────────────────────
echo "── 7. Logical Keymaps ──"
echo ""
grep -E 'LogicalKeymap\(|id:.*"[a-z]' "$SOURCES/Models/LogicalKeymap.swift" 2>/dev/null \
    | grep -E 'id:|name:' | sed 's/^[[:space:]]*//' | head -20
echo ""

# ─────────────────────────────────────────────────────────────────────
# 8. Help articles (what's documented)
# ─────────────────────────────────────────────────────────────────────
echo "── 8. Documented Help Articles ──"
echo ""
for f in "$RESOURCES"/*.md; do
    [[ "$f" == *".prompt.md" ]] && continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    basename_noext=$(basename "$f" .md)
    title=$(head -3 "$f" | grep "^# " | sed 's/^# //')
    echo "  $basename_noext — $title"
done
echo ""

# ─────────────────────────────────────────────────────────────────────
# 9. Features referenced in code but not in help
# ─────────────────────────────────────────────────────────────────────
echo "── 9. All Registered Packs ──"
echo ""
echo "  (AI: compare this list against help articles to find gaps)"
echo ""
grep -B2 -A8 'id: "com\.keypath\.pack\.' "$SOURCES/Services/Packs/PackRegistry.swift" 2>/dev/null \
    | grep -E 'static let|id:|displayName:|tagline:|category:' \
    | sed 's/^[[:space:]]*/  /' | head -80
echo ""

# ─────────────────────────────────────────────────────────────────────
# 10. Experimental features
# ─────────────────────────────────────────────────────────────────────
echo "── 10. Experimental Features ──"
echo ""
grep -rn "\.experimental\|isExperimental\|Experimental" "$SOURCES/Services/RuleCollections/RuleCollectionCatalog.swift" 2>/dev/null \
    | sed 's/^[[:space:]]*//' | head -10
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "  Feed this report to an AI agent for semantic review."
echo "  Run: claude 'Review this help audit report for mismatches'"
echo "═══════════════════════════════════════════════════════════════"
