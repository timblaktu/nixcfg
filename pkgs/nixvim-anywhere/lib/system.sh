#!/usr/bin/env bash
# system.sh - System detection and requirements checking

detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

check_requirements() {
    local system=$(detect_system)
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
        esac
        return 1
    fi
    
    log_success "System requirements satisfied"
}

detect_conflicts() {
    log_step "Detecting potential conflicts..."
    
    local conflicts_found=false
    
    # Check for existing Nix installation
    if [[ -d /nix ]] || command -v nix >/dev/null 2>&1; then
        log_warning "Existing Nix installation detected"
        if command -v home-manager >/dev/null 2>&1; then
            log_info "home-manager already available"
        fi
        conflicts_found=true
    fi
    
    # Check for existing neovim
    if command -v nvim >/dev/null 2>&1; then
        local nvim_path=$(which nvim)
        log_info "Existing neovim found at: $nvim_path"
        
        # Check if it's already from Nix
        if [[ "$nvim_path" == *".nix-profile"* ]]; then
            log_success "Already using Nix-managed neovim"
        else
            log_warning "System neovim will be shadowed by Nix version"
            conflicts_found=true
        fi
    fi
    
    # Check for existing neovim config
    if [[ -d "$HOME/.config/nvim" ]]; then
        log_warning "Existing neovim configuration found at ~/.config/nvim"
        log_info "This will be backed up and replaced with nixvim configuration"
        conflicts_found=true
    fi
    
    if [[ "$conflicts_found" == "true" ]]; then
        echo
        yellow "📋 CONFLICT SUMMARY:"
        if command -v nvim >/dev/null 2>&1 && [[ "$(which nvim)" != *".nix-profile"* ]]; then
            echo "   • System neovim at $(which nvim) will be shadowed"
        fi
        if [[ -d "$HOME/.config/nvim" ]]; then
            local nvim_size=$(du -sh "$HOME/.config/nvim" 2>/dev/null | cut -f1)
            echo "   • Neovim config (~/.config/nvim, $nvim_size) will be replaced"
        fi
        echo "   • Backup will preserve existing configuration"
        echo "   • Use rollback command to restore if needed"
        echo
        log_warning "Potential conflicts detected. Use --force to proceed anyway."
        return 1
    else
        log_success "No conflicts detected"
        return 0
    fi
}
