#!/bin/bash
set -euo pipefail

# KeyPath Version Bump Script
# Updates version in Info.plist files
#
# Usage:
#   ./Scripts/bump-version.sh 1.2.0          # Set specific version
#   ./Scripts/bump-version.sh --patch        # 1.0.0 -> 1.0.1
#   ./Scripts/bump-version.sh --minor        # 1.0.0 -> 1.1.0
#   ./Scripts/bump-version.sh --major        # 1.0.0 -> 2.0.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
INFO_PLIST="$REPO_ROOT/Sources/KeyPathApp/Info.plist"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <version|--patch|--minor|--major>"
    echo ""
    echo "Examples:"
    echo "  $0 1.2.0      # Set specific version"
    echo "  $0 --patch    # 1.0.0 -> 1.0.1"
    echo "  $0 --minor    # 1.0.0 -> 1.1.0"
    echo "  $0 --major    # 1.0.0 -> 2.0.0"
    exit 1
fi

# Get current version
CURRENT=$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
echo "📌 Current version: $CURRENT"

# Parse current version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$1" in
    --patch)
        PATCH=$((PATCH + 1))
        NEW_VERSION="$MAJOR.$MINOR.$PATCH"
        ;;
    --minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        NEW_VERSION="$MAJOR.$MINOR.$PATCH"
        ;;
    --major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        NEW_VERSION="$MAJOR.$MINOR.$PATCH"
        ;;
    *)
        if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            NEW_VERSION="$1"
        else
            echo "❌ Invalid version format: $1"
            echo "   Expected: X.Y.Z (e.g., 1.2.0)"
            exit 1
        fi
        ;;
esac

echo "📝 New version: $NEW_VERSION"

# Update main app Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"
echo "✅ Updated: $INFO_PLIST"

# Update helper Info.plist if it exists
HELPER_PLIST="$REPO_ROOT/Sources/KeyPathHelper/Info.plist"
if [ -f "$HELPER_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$HELPER_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$HELPER_PLIST" 2>/dev/null || true
    echo "✅ Updated: $HELPER_PLIST"
fi

echo ""
echo "🎉 Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
