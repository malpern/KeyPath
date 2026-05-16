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
#   ./Scripts/release.sh --refresh-keyboard-data
#   ./Scripts/release.sh --skip-notarize    # Local release build without notarization

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
INFO_PLIST="$REPO_ROOT/Sources/KeyPathApp/Info.plist"

DRY_RUN=false
SKIP_NOTARIZE=false
REFRESH_KEYBOARD_DATA=false
NEW_VERSION=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            ;;
        --refresh-keyboard-data)
            REFRESH_KEYBOARD_DATA=true
            ;;
        *)
            if [[ $arg =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                NEW_VERSION="$arg"
            else
                echo "❌ Invalid argument: $arg"
                echo "Usage: $0 [--dry-run] [--skip-notarize] [--refresh-keyboard-data] [X.Y.Z]"
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
if [ "$SKIP_NOTARIZE" = true ]; then
    echo "⚠️  Notarization: skipped (--skip-notarize)"
fi
if [ "$REFRESH_KEYBOARD_DATA" = true ]; then
    echo "🗂️  Keyboard data: refresh before build"
fi
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
    if [ "$REFRESH_KEYBOARD_DATA" = true ]; then
        echo "   1. Refresh keyboard detection data"
        echo "   2. Build and sign KeyPath"
        echo "   3. Create Sparkle archive: dist/sparkle/KeyPath-${VERSION}.zip"
        echo "   4. Sign with EdDSA"
        echo "   5. Generate appcast entry"
    else
        echo "   1. Build and sign KeyPath"
        echo "   2. Create Sparkle archive: dist/sparkle/KeyPath-${VERSION}.zip"
        echo "   3. Sign with EdDSA"
        echo "   4. Generate appcast entry"
    fi
    NEXT_STEP=5
    if [ "$REFRESH_KEYBOARD_DATA" = true ]; then
        NEXT_STEP=6
    fi
    echo ""
    echo "   Then you would:"
    echo "   ${NEXT_STEP}. git add -A && git commit -m 'chore: release v${VERSION}'"
    echo "   $((NEXT_STEP + 1)). git tag v${VERSION}"
    echo "   $((NEXT_STEP + 2)). git push origin main --tags"
    echo "   $((NEXT_STEP + 3)). Create GitHub Release and upload ZIP"
    echo "   $((NEXT_STEP + 4)). Update appcast.xml with generated entry"
    echo "   $((NEXT_STEP + 5)). git add appcast.xml && git commit -m 'chore: update appcast for v${VERSION}'"
    echo "   $((NEXT_STEP + 6)). git push"
    echo ""
    exit 0
fi

if [ "$REFRESH_KEYBOARD_DATA" = true ]; then
    echo "🗂️ Refreshing keyboard detection data..."
    chmod +x ./Scripts/refresh-keyboard-detection-data.sh
    ./Scripts/refresh-keyboard-detection-data.sh
fi

# Build the release
echo "🔨 Building release..."
if [ "$SKIP_NOTARIZE" = true ]; then
    SKIP_NOTARIZE=1 ./build.sh
else
    ./build.sh
fi

# Check that Sparkle archive was created
SPARKLE_ZIP="dist/sparkle/KeyPath-${VERSION}.zip"
if [ ! -f "$SPARKLE_ZIP" ]; then
    echo "❌ ERROR: Sparkle archive not found: $SPARKLE_ZIP"
    exit 1
fi

SPARKLE_DMG="dist/sparkle/KeyPath-${VERSION}.dmg"
APPCAST_ENTRY="dist/sparkle/KeyPath-${VERSION}.zip.appcast-entry.xml"

echo ""
echo "✅ Release build complete!"
echo ""
echo "📦 Artifacts:"
echo "   • dist/KeyPath.app"
echo "   • $SPARKLE_ZIP"
echo "   • $SPARKLE_DMG"
echo "   • $APPCAST_ENTRY"
echo ""

# --- Automated release steps ---

echo "🏷️  Creating git tag v${VERSION}..."
git tag -f "v${VERSION}"

echo "📤 Creating GitHub Release..."
gh release create "v${VERSION}" \
    "$SPARKLE_ZIP" \
    "$SPARKLE_DMG" \
    --title "KeyPath ${VERSION}" \
    --prerelease \
    --notes "See [release notes](https://github.com/malpern/KeyPath/releases/tag/v${VERSION}) for details."

echo "📝 Updating appcast.xml..."
if [ -f "$APPCAST_ENTRY" ]; then
    # Insert the new entry after the "Releases go here" comment
    ENTRY_CONTENT=$(cat "$APPCAST_ENTRY" | grep -v "^<!--" | sed 's/^/        /')
    # Use python for reliable XML insertion (sed struggles with multiline)
    python3 -c "
import sys
appcast = open('appcast.xml').read()
entry = open('$APPCAST_ENTRY').read()
# Strip the comment line from the entry
lines = [l for l in entry.splitlines() if not l.strip().startswith('<!--')]
entry_clean = '\n'.join(lines)
# Indent each line with 8 spaces for XML formatting
indented = '\n'.join('        ' + l.lstrip() if l.strip() else '' for l in entry_clean.splitlines())
marker = '<!-- Releases go here (newest first) -->'
if marker in appcast:
    appcast = appcast.replace(marker, marker + '\n\n' + indented.rstrip())
    open('appcast.xml', 'w').write(appcast)
    print('   ✅ Appcast updated')
else:
    print('   ⚠️  Could not find marker in appcast.xml — update manually')
    sys.exit(1)
"
    git add appcast.xml
    git commit -m "chore: update appcast for v${VERSION}"
else
    echo "   ⚠️  Appcast entry not found at $APPCAST_ENTRY — update manually"
fi

echo "🌐 Updating gh-pages download link..."
GHPAGES_WORKTREE=$(mktemp -d)
git worktree add "$GHPAGES_WORKTREE" gh-pages 2>/dev/null

DMG_URL="https://github.com/malpern/KeyPath/releases/download/v${VERSION}/KeyPath-${VERSION}.dmg"
if [ -f "$GHPAGES_WORKTREE/index.md" ]; then
    # Replace any existing DMG download link with the new version
    sed -i '' "s|https://github.com/malpern/KeyPath/releases/download/[^\"]*\.dmg|${DMG_URL}|g" "$GHPAGES_WORKTREE/index.md"
    cd "$GHPAGES_WORKTREE"
    git add index.md
    if git diff --cached --quiet; then
        echo "   ℹ️  Download link already current"
    else
        git commit -m "chore: update download link to v${VERSION}"
        git push origin gh-pages --no-verify
        echo "   ✅ gh-pages download link updated"
    fi
    cd "$REPO_ROOT"
else
    echo "   ⚠️  index.md not found on gh-pages — update manually"
fi
git worktree remove "$GHPAGES_WORKTREE" 2>/dev/null || true

echo "🍺 Updating Homebrew cask..."
HOMEBREW_TAP="/opt/homebrew/Library/Taps/malpern/homebrew-tap"
if [ -d "$HOMEBREW_TAP" ]; then
    DMG_SHA256=$(shasum -a 256 "$SPARKLE_DMG" | awk '{print $1}')
    CASK_FILE="$HOMEBREW_TAP/Casks/keypath.rb"
    if [ -f "$CASK_FILE" ]; then
        sed -i '' "s|version \".*\"|version \"${VERSION}\"|" "$CASK_FILE"
        sed -i '' "s|sha256 \".*\"|sha256 \"${DMG_SHA256}\"|" "$CASK_FILE"
        cd "$HOMEBREW_TAP"
        git add Casks/keypath.rb
        git commit -m "chore: update keypath cask to v${VERSION}"
        git push
        echo "   ✅ Homebrew cask updated to v${VERSION}"
        cd "$REPO_ROOT"
    else
        echo "   ⚠️  Cask file not found at $CASK_FILE — update manually"
    fi
else
    echo "   ⚠️  Homebrew tap not found — run: brew tap malpern/tap"
fi

echo ""
echo "🎉 Release v${VERSION} published!"
echo "   • GitHub Release: https://github.com/malpern/KeyPath/releases/tag/v${VERSION}"
echo "   • Sparkle update will reach users within 24 hours"
echo "   • Website download link updated"
echo "   • Homebrew cask updated"
echo ""
echo "📋 Remaining manual steps:"
echo "   1. Write release notes on the GitHub Release page"
echo "   2. Push the appcast commit: git push"
