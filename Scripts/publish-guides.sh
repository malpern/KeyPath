#!/bin/bash
# Publish guides from master to the gh-pages branch.
# Copies all guides/*.md files and syncs docs.md if changed.
#
# Usage:
#   ./Scripts/publish-guides.sh              # publish all guides
#   ./Scripts/publish-guides.sh cli.md       # publish specific guide(s)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHPAGES_WORKTREE="$REPO_ROOT/.worktrees/gh-pages"

if [ ! -d "$GHPAGES_WORKTREE" ]; then
    echo "Creating gh-pages worktree..."
    git worktree add "$GHPAGES_WORKTREE" gh-pages
fi

cd "$GHPAGES_WORKTREE"
git pull origin gh-pages --ff-only 2>/dev/null || true

if [ $# -gt 0 ]; then
    # Publish specific guides
    for guide in "$@"; do
        src="$REPO_ROOT/guides/$guide"
        if [ -f "$src" ]; then
            cp "$src" "$GHPAGES_WORKTREE/guides/$guide"
            echo "  copied guides/$guide"
        else
            echo "  ⚠️  guides/$guide not found on master"
        fi
    done
else
    # Publish all guides
    for src in "$REPO_ROOT"/guides/*.md; do
        name=$(basename "$src")
        cp "$src" "$GHPAGES_WORKTREE/guides/$name"
    done
    echo "  copied all guides/*.md"
fi

# Check for changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "✅ No changes to publish"
    exit 0
fi

git add guides/
CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
git commit -m "Publish $CHANGED guide(s) from master $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
git push origin gh-pages
echo "✅ Published to gh-pages"
