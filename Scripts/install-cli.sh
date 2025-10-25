#!/usr/bin/env bash
set -euo pipefail

# KeyPath CLI installer
# Installs the 'keypath' binary built by SwiftPM into a bin directory.
#
# Usage:
#   Scripts/install-cli.sh [--user] [--prefix <dir>] [--link] [--force]
#
# Options:
#   --user            Install to "$HOME/.local/bin" (no sudo needed)
#   --prefix <dir>    Install under <dir>/bin (default: /opt/homebrew or /usr/local)
#   --link            Create a symlink to the built binary (useful for dev)
#   --force           Overwrite existing binary/symlink if present

PREFIX=""
MODE="copy"   # or "link"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      PREFIX="$HOME/.local"
      shift
      ;;
    --prefix)
      PREFIX="${2:-}"
      [[ -n "$PREFIX" ]] || { echo "--prefix requires a value" >&2; exit 2; }
      shift 2
      ;;
    --link)
      MODE="link"
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--user] [--prefix <dir>] [--link] [--force]"; exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2; exit 2
      ;;
  esac
done

# Choose a sensible default prefix if not provided
if [[ -z "$PREFIX" ]]; then
  if [[ -d "/opt/homebrew/bin" ]]; then
    PREFIX="/opt/homebrew"
  else
    PREFIX="/usr/local"
  fi
fi

DEST_DIR="$PREFIX/bin"
DEST_BIN="$DEST_DIR/keypath"

echo "📦 Building CLI (release)…"
BIN_DIR=$(swift build -c release --product keypath --show-bin-path)
SRC_BIN="$BIN_DIR/keypath"

if [[ ! -x "$SRC_BIN" ]]; then
  echo "❌ Built CLI not found at $SRC_BIN" >&2
  exit 1
fi

echo "📁 Ensuring destination: $DEST_DIR"
mkdir -p "$DEST_DIR"

if [[ -e "$DEST_BIN" && $FORCE == false ]]; then
  echo "❌ $DEST_BIN already exists. Use --force to overwrite, or choose --prefix/--user." >&2
  exit 2
fi

if [[ "$MODE" == "link" ]]; then
  echo "🔗 Linking $DEST_BIN -> $SRC_BIN"
  ln -sf "$SRC_BIN" "$DEST_BIN"
else
  echo "📤 Installing $SRC_BIN -> $DEST_BIN"
  cp -f "$SRC_BIN" "$DEST_BIN"
fi

chmod +x "$DEST_BIN"

# Post-install check
if command -v keypath >/dev/null 2>&1; then
  WHICH=$(command -v keypath)
  echo "✅ Installed: $WHICH"
else
  echo "⚠️ keypath is not on your PATH. Add '$DEST_DIR' to PATH, e.g.:" >&2
  echo "   echo 'export PATH=\"$DEST_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" >&2
fi

echo "ℹ️  Try: keypath --help"

