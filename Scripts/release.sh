#!/bin/bash
set -euo pipefail

# KeyPath Release Script
# Creates a release build and prepares it for GitHub release
#
# Usage:
#   ./Scripts/release.sh                    # Uses current version from Info.plist
#   ./Scripts/release.sh 1.2.0              # Bumps to specified version first
#   ./Scripts/release.sh --dry-run          # Show what would happen without doing it
#   ./Scripts/release.sh --dry-run 1.2.0    # Dry run with version bump

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
INFO_PLIST="$REPO_ROOT/Sources/KeyPathApp/Info.plist"

DRY_RUN=false
NEW_VERSION=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            if [[ $arg =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                NEW_VERSION="$arg"
            else
                echo "❌ Invalid argument: $arg"
                echo "Usage: $0 [--dry-run] [X.Y.Z]"
                exit 1
            fi
            ;;
    esac
done

cd "$REPO_ROOT"

echo "🚀 KeyPath Release Script"
echo "========================="
echo ""

# Get current version
CURRENT_VERSION=$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
echo "📌 Current version: $CURRENT_VERSION"

# Bump version if specified
if [ -n "$NEW_VERSION" ]; then
    echo "📝 Bumping version to: $NEW_VERSION"
    
    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would update Info.plist"
    else
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"
        echo "   ✅ Updated Info.plist"
    fi
    
    VERSION="$NEW_VERSION"
else
    VERSION="$CURRENT_VERSION"
fi

echo ""
echo "🎯 Release version: $VERSION"
echo ""

# Check for uncommitted changes
if ! git diff --quiet HEAD -- 2>/dev/null; then
    echo "⚠️  Warning: You have uncommitted changes"
    git status --short
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

if [ "$DRY_RUN" = true ]; then
    echo "🔍 [DRY RUN] Would perform the following steps:"
    echo ""
    echo "   1. Build and sign KeyPath"
    echo "   2. Create Sparkle archive: dist/sparkle/KeyPath-${VERSION}.zip"
    echo "   3. Sign with EdDSA"
    echo "   4. Generate appcast entry"
    echo ""
    echo "   Then you would:"
    echo "   5. git add -A && git commit -m 'chore: release v${VERSION}'"
    echo "   6. git tag v${VERSION}"
    echo "   7. git push origin main --tags"
    echo "   8. Create GitHub Release and upload ZIP"
    echo "   9. Update appcast.xml with generated entry"
    echo "   10. git add appcast.xml && git commit -m 'chore: update appcast for v${VERSION}'"
    echo "   11. git push"
    echo ""
    exit 0
fi

# Build the release
echo "🔨 Building release..."
./build.sh

# Check that Sparkle archive was created
SPARKLE_ZIP="dist/sparkle/KeyPath-${VERSION}.zip"
if [ ! -f "$SPARKLE_ZIP" ]; then
    echo "❌ ERROR: Sparkle archive not found: $SPARKLE_ZIP"
    exit 1
fi

echo ""
echo "✅ Release build complete!"
echo ""
echo "📦 Artifacts created:"
echo "   • dist/KeyPath.app (installed to /Applications)"
echo "   • dist/sparkle/KeyPath-${VERSION}.zip (for GitHub Release)"
echo "   • dist/sparkle/KeyPath-${VERSION}.zip.sig (EdDSA signature)"
echo "   • dist/sparkle/KeyPath-${VERSION}.appcast-entry.xml"
echo ""
echo "📋 Next steps:"
echo ""
echo "   1. Commit the version bump (if any):"
echo "      git add -A && git commit -m 'chore: release v${VERSION}'"
echo ""
echo "   2. Create and push the tag:"
echo "      git tag v${VERSION}"
echo "      git push origin main --tags"
echo ""
echo "   3. Create GitHub Release:"
echo "      gh release create v${VERSION} '$SPARKLE_ZIP' --title 'KeyPath ${VERSION}' --notes 'Release notes here'"
echo ""
echo "   4. Update appcast.xml:"
echo "      - Copy contents of dist/sparkle/KeyPath-${VERSION}.appcast-entry.xml"
echo "      - Paste into appcast.xml (newest release first)"
echo "      - git add appcast.xml && git commit -m 'chore: update appcast for v${VERSION}'"
echo "      - git push"
echo ""
echo "🎉 Done! Users will see the update within 24 hours (or immediately if they check manually)."
