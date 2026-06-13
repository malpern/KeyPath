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
#   ./Scripts/release.sh --no-doctor        # Skip release-doctor preflight

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
INFO_PLIST="$REPO_ROOT/Sources/KeyPathApp/Info.plist"

DRY_RUN=false
SKIP_NOTARIZE=false
REFRESH_KEYBOARD_DATA=false
RUN_DOCTOR=true
NEW_VERSION=""
TEMP_GHPAGES_WORKTREE=""

cleanup() {
    if [ -n "$TEMP_GHPAGES_WORKTREE" ]; then
        git worktree remove "$TEMP_GHPAGES_WORKTREE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

find_worktree_for_branch() {
    local branch_name=$1
    git worktree list --porcelain | awk -v target="refs/heads/${branch_name}" '
        /^worktree / { path=substr($0, 10) }
        /^branch / {
            if ($2 == target) {
                print path
                exit
            }
        }
    '
}

usage() {
    echo "Usage: $0 [--dry-run] [--no-doctor] [--refresh-keyboard-data] [--skip-notarize dry-run only] [X.Y.Z]"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            ;;
        --no-doctor)
            RUN_DOCTOR=false
            ;;
        --refresh-keyboard-data)
            REFRESH_KEYBOARD_DATA=true
            ;;
        *)
            if [[ $arg =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                NEW_VERSION="$arg"
            else
                echo "❌ Invalid argument: $arg"
                usage
                exit 1
            fi
            ;;
    esac
done

cd "$REPO_ROOT"

echo "🚀 KeyPath Release Script"
echo "========================="
echo ""

if [ "$SKIP_NOTARIZE" = true ] && [ "$DRY_RUN" = false ]; then
    echo "❌ ERROR: release.sh publishes public artifacts and must notarize them."
    echo "   Use ./build.sh or ./Scripts/release-candidate.sh for local unnotarized testing."
    exit 1
fi

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
    echo "⚠️  Notarization: skipped (--skip-notarize dry-run only)"
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
    STEP=1
    if [ "$RUN_DOCTOR" = true ]; then
        echo "   ${STEP}. Run release-doctor ship preflight"
        STEP=$((STEP + 1))
    fi
    if [ "$REFRESH_KEYBOARD_DATA" = true ]; then
        echo "   ${STEP}. Refresh keyboard detection data"
        STEP=$((STEP + 1))
    fi
    if [ "$SKIP_NOTARIZE" = true ]; then
        echo "   ${STEP}. Build/sign KeyPath without notarization (dry-run only)"
    else
        echo "   ${STEP}. Build, sign, notarize, and staple KeyPath"
    fi
    STEP=$((STEP + 1))
    echo "   ${STEP}. Create Sparkle archive: dist/sparkle/KeyPath-${VERSION}.zip"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Sign Sparkle archive with EdDSA"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Create DMG: dist/sparkle/KeyPath-${VERSION}.dmg"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Generate appcast entry"
    STEP=$((STEP + 1))
    echo ""
    echo "   Then you would:"
    echo "   ${STEP}. git tag v${VERSION}"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Create GitHub Release and upload ZIP + DMG"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Update appcast.xml with generated entry"
    STEP=$((STEP + 1))
    echo "   ${STEP}. git add appcast.xml && git commit -m 'chore: update appcast for v${VERSION}'"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Update and push gh-pages download links"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Update and push Homebrew cask if the local tap is installed"
    STEP=$((STEP + 1))
    echo "   ${STEP}. Push appcast commit and tag: git push origin master --tags"
    echo ""
    exit 0
fi

if [ "$RUN_DOCTOR" = true ] && [ "${SKIP_RELEASE_DOCTOR:-0}" != "1" ]; then
    echo "🩺 Running release preflight..."
    ./Scripts/release-doctor.sh --ship
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
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "❌ Tag v${VERSION} already exists. Bump the version or delete the tag manually." >&2
    exit 1
fi
git tag "v${VERSION}"

echo "📤 Creating GitHub Release..."
# Mark as pre-release only for versions carrying a semver pre-release suffix
# (e.g. 1.0.0-beta4). Stable versions (1.0.0) publish as "Latest release".
# Scalar + ${x:+...} keeps this safe under `set -u` on bash 3.2 (macOS).
PRERELEASE_FLAG=""
if [[ "$VERSION" == *-* ]]; then
    PRERELEASE_FLAG="--prerelease"
    echo "   $VERSION is a pre-release → marking GitHub Release as pre-release"
else
    echo "   $VERSION is stable → publishing as Latest release"
fi
gh release create "v${VERSION}" \
    "$SPARKLE_ZIP" \
    "$SPARKLE_DMG" \
    --title "KeyPath ${VERSION}" \
    ${PRERELEASE_FLAG:+"$PRERELEASE_FLAG"} \
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
GHPAGES_WORKTREE=$(find_worktree_for_branch gh-pages)
if [ -n "$GHPAGES_WORKTREE" ]; then
    echo "   Using existing gh-pages worktree: $GHPAGES_WORKTREE"
else
    TEMP_GHPAGES_WORKTREE=$(mktemp -d)
    GHPAGES_WORKTREE="$TEMP_GHPAGES_WORKTREE"
    git worktree add "$GHPAGES_WORKTREE" gh-pages
fi

if ! git -C "$GHPAGES_WORKTREE" diff --quiet || ! git -C "$GHPAGES_WORKTREE" diff --cached --quiet; then
    echo "❌ gh-pages worktree has uncommitted tracked changes: $GHPAGES_WORKTREE" >&2
    exit 1
fi

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
        git push origin gh-pages
        echo "   ✅ gh-pages download link updated"
    fi
    cd "$REPO_ROOT"
else
    echo "   ⚠️  index.md not found on gh-pages — update manually"
fi

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
