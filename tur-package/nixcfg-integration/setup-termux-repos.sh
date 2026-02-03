#!/data/data/com.termux/files/usr/bin/bash
##
## Termux Repository Setup Script
##
## Adds custom APT repositories and installs packages for Claude Code multi-account setup.
## This script is designed to run on Termux (not via Nix home-manager).
##

set -euo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Termux Custom Repository Setup                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ─── Repository Configuration ─────────────────────────────────────

REPO_NAME="timblaktu-tur"
REPO_URL="https://timblaktu.github.io/tur"
REPO_SUITE="stable"
REPO_COMPONENT="main"
REPO_FILE="$PREFIX/etc/apt/sources.list.d/${REPO_NAME}.list"

echo "Repository: $REPO_NAME"
echo "URL: $REPO_URL"
echo ""

# ─── Check if Already Configured ──────────────────────────────────

if [[ -f "$REPO_FILE" ]]; then
  echo "⚠️  Repository already configured at:"
  echo "    $REPO_FILE"
  echo ""
  read -p "Reconfigure anyway? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
  fi
  rm -f "$REPO_FILE"
fi

# ─── Add Repository ───────────────────────────────────────────────

echo "Adding repository..."
echo "deb [trusted=yes] ${REPO_URL} ${REPO_SUITE} ${REPO_COMPONENT}" | \
  tee "$REPO_FILE"

echo "✅ Repository added"
echo ""

# ─── Update Package Lists ─────────────────────────────────────────

echo "Updating package lists..."
if ! pkg update; then
  echo ""
  echo "❌ Error: Failed to update package lists" >&2
  echo "   Check your internet connection and repository URL" >&2
  exit 1
fi

echo "✅ Package lists updated"
echo ""

# ─── Show Available Packages ──────────────────────────────────────

echo "Available packages from $REPO_NAME:"
echo ""
pkg search -o APT::Cache::ShowVersion=true claude 2>/dev/null || \
  echo "  (No packages found - repository may be empty or not yet published)"
echo ""

# ─── Offer to Install ─────────────────────────────────────────────

echo "Install packages now? [y/N] "
read -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Installing packages..."

  # Check if Claude Code is installed
  if ! command -v claude &> /dev/null; then
    echo ""
    echo "⚠️  Claude Code not found"
    echo "   Install it first? [y/N] "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Installing Node.js LTS..."
      pkg install -y nodejs-lts

      echo "Installing Claude Code..."
      npm install -g @anthropic/claude-code

      echo "✅ Claude Code installed"
      echo ""
    else
      echo "⚠️  Warning: Claude Code wrappers require Claude Code to be installed"
      echo "   Install it later with: npm install -g @anthropic/claude-code"
      echo ""
    fi
  fi

  # Install claude-wrappers
  if pkg show claude-wrappers &>/dev/null; then
    echo "Installing claude-wrappers..."
    pkg install -y claude-wrappers

    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "Available commands:"
    echo "  claudemax   - Claude Max account"
    echo "  claudepro   - Claude Pro account"
    echo "  claudework  - Work Code-Companion proxy"
    echo ""
    echo "Setup work account:"
    echo "  claude-setup-work"
    echo ""
  else
    echo "❌ Package 'claude-wrappers' not found in repository" >&2
    echo "   The package may not be published yet" >&2
    exit 1
  fi
else
  echo "Skipped installation."
  echo ""
  echo "Install later with:"
  echo "  pkg install claude-wrappers"
  echo ""
fi

echo "Setup complete!"
echo ""
echo "Repository file: $REPO_FILE"
echo "Documentation: $PREFIX/share/doc/claude-wrappers/README.md"
echo ""
