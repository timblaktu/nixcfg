#!/usr/bin/env bash
# common.sh - Common constants, colors, and logging functions

# Configuration
BACKUP_BASE_DIR="$HOME/.nixvim-anywhere-backups"
CONFIG_TARGET="${CONFIG_TARGET:-tim@nixvim-minimal}"
DRY_RUN="${DRY_RUN:-false}"
VERSION="1.0.0"

# Colors and output functions
red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }
bold() { echo -e "\033[1m$*\033[0m"; }

log_info() { echo "ℹ️  $*"; }
log_success() { green "✅ $*"; }
log_warning() { yellow "⚠️  $*"; }
log_error() { red "❌ $*"; }
log_step() { blue "🔧 $*"; }

print_header() {
    bold "=== nixvim-anywhere v$VERSION ==="
    echo "Convert any system to use nixvim via Nix + home-manager"
    echo "Safe installation with backup and rollback capabilities"
    echo
}

print_usage() {
    bold "USAGE:"
    echo "  $SCRIPT_NAME <command> [options]"
    echo
    bold "COMMANDS:"
    echo "  install                 Convert system to use nixvim via home-manager"
    echo "  validate                Check current installation status"
    echo "  status                  Show system and installation status"
    echo "  backup                  Create backup of current state"
    echo "  rollback                Restore pre-Nix system state"
    echo "  uninstall               Completely remove Nix and home-manager"
    echo "  help                    Show this help message"
    echo
    bold "OPTIONS:"
    echo "  --backup                Create backup before installation (recommended)"
    echo "  --dry-run               Show what would be done without making changes"
    echo "  --target CONFIG         Use specific nixvim configuration target"
    echo "  --detect-conflicts      Check for potential conflicts before installation"
    echo "  --force                 Proceed even if conflicts detected"
    echo "  --minimal               Install only Nix, skip home-manager setup"
    echo
    bold "EXAMPLES:"
    echo "  $SCRIPT_NAME install --backup --detect-conflicts"
    echo "  $SCRIPT_NAME install --target tim@mbp --backup"
    echo "  $SCRIPT_NAME validate"
    echo "  $SCRIPT_NAME rollback"
    echo
}
