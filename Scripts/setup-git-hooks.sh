#!/bin/bash
#
# Setup Git Hooks for KeyPath
# Installs pre-commit hook for code quality checks
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔧 Setting up KeyPath Git Hooks"
echo "==============================="

cd "$PROJECT_ROOT"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Not in a git repository"
    exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p .git/hooks

# Copy pre-commit hook
echo "📝 Installing pre-commit hook..."
cp "$SCRIPT_DIR/../.git/hooks/pre-commit" .git/hooks/pre-commit.keypath-template

# Check if hook already exists
if [ -f ".git/hooks/pre-commit" ]; then
    echo "⚠️  Pre-commit hook already exists"
    echo ""
    echo "Options:"
    echo "  1. Backup existing and install new (recommended)"
    echo "  2. Skip installation"
    echo ""
    read -p "Choose option (1/2): " choice
    
    case $choice in
        1)
            mv .git/hooks/pre-commit .git/hooks/pre-commit.backup
            cp .git/hooks/pre-commit.keypath-template .git/hooks/pre-commit
            chmod +x .git/hooks/pre-commit
            echo "✅ Pre-commit hook installed (backup saved)"
            ;;
        2)
            echo "⏭️  Skipping hook installation"
            rm .git/hooks/pre-commit.keypath-template
            ;;
        *)
            echo "❌ Invalid choice"
            exit 1
            ;;
    esac
else
    cp .git/hooks/pre-commit.keypath-template .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "✅ Pre-commit hook installed"
fi

# Clean up template
rm -f .git/hooks/pre-commit.keypath-template

echo ""
echo "🔍 Hook Configuration:"
echo "  🚀 Full build, sign, and deploy (creates testable app)"
echo "  📝 SwiftLint (if installed)"
echo "  🎨 SwiftFormat check (if installed)"
echo "  🔍 Critical code pattern checks"
echo ""

# Check for optional tools
echo "📦 Optional Tools Status:"
if command -v swiftlint >/dev/null 2>&1; then
    echo "  ✅ SwiftLint installed"
else
    echo "  ⚪ SwiftLint not installed (install with: brew install swiftlint)"
fi

if command -v swiftformat >/dev/null 2>&1; then
    echo "  ✅ SwiftFormat installed"
else
    echo "  ⚪ SwiftFormat not installed (install with: brew install swiftformat)"
fi

echo ""
echo "💡 Usage:"
echo "  • Hook runs automatically on 'git commit'"
echo "  • Skip with 'git commit --no-verify' if needed"
echo "  • Hook builds, signs, and deploys (~2-3 minutes)"
echo "  • Every commit gives you a testable app in /Applications/"
echo "  • CI still runs comprehensive tests for validation"
echo ""
echo "⚠️  Note: Hook will take longer now (~2-3 min) but gives you instant testing!"
echo ""
echo "🎉 Git hooks setup complete!"