#!/usr/bin/env bash
# install-nixvim-anywhere.sh
# Web installer for nixvim-anywhere - convert any system to use nixvim via Nix + home-manager
# Usage: curl -L https://github.com/tim/nixcfg/raw/main/install-nixvim-anywhere.sh | bash

set -euo pipefail

# Configuration
REPO_URL="https://github.com/tim/nixcfg"
TEMP_DIR="/tmp/nixvim-anywhere-installer-$(date +%s)"
SCRIPT_VERSION="1.0.0"

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
    bold "=== nixvim-anywhere Web Installer v$SCRIPT_VERSION ==="
    echo "Convert any system to use nixvim via Nix + home-manager"
    echo "Safe installation with backup and rollback capabilities"
    echo
    log_info "This installer will:"
    echo "  • Install Nix in single-user mode (safe, no daemon)"
    echo "  • Set up home-manager for user-space package management"
    echo "  • Deploy nixvim with all dependencies (LSP servers, tools)"
    echo "  • Create backups of existing configurations"
    echo "  • Validate installation to ensure everything works"
    echo
}

check_system_requirements() {
    log_step "Checking system requirements"
    
    # Check OS compatibility
    local system="unknown"
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        system="$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        system="macos"
    fi
    
    log_info "Detected system: $system"
    
    # Check for required tools
    local missing_tools=()
    for tool in curl git bash; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo
        echo "Please install these tools using your system package manager:"
        case "$system" in
            ubuntu|debian)
                echo "  sudo apt update && sudo apt install -y ${missing_tools[*]}"
                ;;
            fedora|rhel|centos)
                echo "  sudo dnf install -y ${missing_tools[*]}"
                ;;
            arch)
                echo "  sudo pacman -S ${missing_tools[*]}"
                ;;
            macos)
                echo "  Install Command Line Tools: xcode-select --install"
                ;;
            *)
                echo "  Install using your system package manager"
                ;;
        esac
        exit 1
    fi
    
    log_success "System requirements satisfied"
}

warn_about_changes() {
    log_warning "IMPORTANT: This installer will make changes to your system"
    echo
    echo "Changes that will be made:"
    echo "  • Install Nix package manager in ~/.nix-profile (user-space only)"
    echo "  • Install home-manager for declarative user environment"
    echo "  • Replace current neovim configuration with nixvim"
    echo "  • Add Nix to your shell PATH"
    echo
    echo "Safety measures:"
    echo "  • No root/system-wide changes (single-user Nix installation)"
    echo "  • Comprehensive backup of existing configurations"
    echo "  • Easy rollback to pre-installation state"
    echo "  • Can be completely uninstalled if needed"
    echo
    
    read -p "Do you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

download_nixvim_anywhere() {
    log_step "Downloading nixvim-anywhere from $REPO_URL"
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository
    log_info "Cloning repository..."
    if ! git clone --depth 1 "$REPO_URL" .; then
        log_error "Failed to clone repository"
        echo "Please check your internet connection and try again"
        exit 1
    fi
    
    # Verify nixvim-anywhere script exists
    if [[ ! -f "pkgs/nixvim-anywhere/nixvim-anywhere" ]]; then
        log_error "nixvim-anywhere script not found in repository"
        echo "Repository structure may have changed"
        exit 1
    fi
    
    chmod +x pkgs/nixvim-anywhere/nixvim-anywhere
    log_success "nixvim-anywhere downloaded successfully"
}

run_installation() {
    log_step "Running nixvim-anywhere installation"
    
    cd "$TEMP_DIR"
    
    # Run the main installation with recommended options
    if ./pkgs/nixvim-anywhere/nixvim-anywhere install --backup --detect-conflicts; then
        log_success "nixvim-anywhere installation completed successfully!"
    else
        log_error "nixvim-anywhere installation failed"
        echo
        echo "Troubleshooting:"
        echo "  • Check the error messages above"
        echo "  • Verify system requirements are met"
        echo "  • Try manual installation: ./pkgs/nixvim-anywhere/nixvim-anywhere install --backup --force"
        echo "  • For support, check: https://github.com/tim/nixcfg/issues"
        exit 1
    fi
}

post_installation_steps() {
    log_success "Installation complete! 🎉"
    echo
    echo "Next steps:"
    echo "1. **Restart your shell** or run: source ~/.nix-profile/etc/profile.d/nix.sh"
    echo "2. **Test neovim**: nvim"
    echo "3. **Update configuration**: home-manager switch"
    echo
    echo "Useful commands:"
    echo "  • Check status: nixvim-anywhere status"
    echo "  • Validate setup: nixvim-anywhere validate"
    echo "  • Update config: home-manager switch"
    echo "  • Rollback if needed: nixvim-anywhere rollback"
    echo
    log_info "Your nixvim configuration is now managed by Nix + home-manager!"
    echo "All LSP servers and dependencies are automatically managed."
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

main() {
    print_header
    
    # Check if user wants to proceed
    warn_about_changes
    
    # Verify system can run the installer
    check_system_requirements
    
    # Download nixvim-anywhere
    download_nixvim_anywhere
    
    # Run the installation
    run_installation
    
    # Show next steps
    post_installation_steps
}

# Handle command line arguments
case "${1:-install}" in
    install)
        main
        ;;
    --help|-h|help)
        print_header
        echo "This is the web installer for nixvim-anywhere."
        echo "It downloads and runs the full nixvim-anywhere installation."
        echo
        echo "Usage:"
        echo "  curl -L https://github.com/tim/nixcfg/raw/main/install-nixvim-anywhere.sh | bash"
        echo
        echo "For manual installation:"
        echo "  git clone https://github.com/tim/nixcfg.git"
        echo "  cd nixcfg/pkgs/nixvim-anywhere"
        echo "  ./nixvim-anywhere install --backup"
        echo
        echo "For more information:"
        echo "  https://github.com/tim/nixcfg/blob/main/pkgs/nixvim-anywhere/README.md"
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
