#!/usr/bin/env bash
# validation.sh - Status checking and validation functions

validate_installation() {
    log_step "Validating installation"
    
    local errors=0
    
    # Check Nix installation
    if command -v nix >/dev/null 2>&1; then
        log_success "Nix available: $(nix --version | head -1)"
    else
        log_error "Nix not found in PATH"
        ((errors++))
    fi
    
    # Check home-manager
    if command -v home-manager >/dev/null 2>&1; then
        log_success "home-manager available: $(home-manager --version)"
    else
        log_error "home-manager not found in PATH"
        ((errors++))
    fi
    
    # Check neovim
    if command -v nvim >/dev/null 2>&1; then
        local nvim_path=$(which nvim)
        log_success "neovim available: $nvim_path"
        
        # Check if it's Nix-managed
        if [[ "$nvim_path" == *".nix-profile"* ]]; then
            log_success "Using Nix-managed neovim"
        else
            log_warning "Using system neovim, not Nix version"
            ((errors++))
        fi
        
        # Test neovim startup
        if nvim --version >/dev/null 2>&1; then
            log_success "neovim startup test passed"
        else
            log_error "neovim startup test failed"
            ((errors++))
        fi
    else
        log_error "neovim not found in PATH"
        ((errors++))
    fi
    
    # Check configuration
    if [[ -f "$HOME/.config/home-manager/home.nix" ]]; then
        log_success "home-manager configuration exists"
    else
        log_error "home-manager configuration missing"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All validation checks passed!"
        echo
        echo "🎉 nixvim-anywhere installation successful!"
        echo "You can now use 'nvim' to start your Nix-managed neovim with nixvim configuration."
        echo
        echo "Next steps:"
        echo "1. Restart your shell or run: source ~/.nix-profile/etc/profile.d/nix.sh"
        echo "2. Test neovim: nvim"
        echo "3. Update configuration: home-manager switch"
        return 0
    else
        log_error "Validation failed with $errors errors"
        return 1
    fi
}

show_status() {
    bold "=== nixvim-anywhere Status ==="
    echo
    
    # System info
    echo "System: $(detect_system)"
    echo "User: $(whoami)"
    echo "Home: $HOME"
    echo
    
    # Nix status
    if command -v nix >/dev/null 2>&1; then
        echo "✅ Nix: $(nix --version | head -1)"
    else
        echo "❌ Nix: Not installed"
    fi
    
    # home-manager status
    if command -v home-manager >/dev/null 2>&1; then
        echo "✅ home-manager: $(home-manager --version)"
    else
        echo "❌ home-manager: Not installed"
    fi
    
    # neovim status
    if command -v nvim >/dev/null 2>&1; then
        local nvim_path=$(which nvim)
        echo "✅ neovim: $nvim_path"
        if [[ "$nvim_path" == *".nix-profile"* ]]; then
            echo "   📦 Managed by: Nix"
        else
            echo "   📦 Managed by: System package manager"
        fi
    else
        echo "❌ neovim: Not installed"
    fi
    
    # Configuration status
    if [[ -f "$HOME/.config/home-manager/home.nix" ]]; then
        echo "✅ home-manager config: ~/.config/home-manager/home.nix"
    else
        echo "❌ home-manager config: Not found"
    fi
    
    # Available backups
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        local backup_count=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
        echo "💾 Backups: $((backup_count - 1)) available in $BACKUP_BASE_DIR"
    else
        echo "💾 Backups: None found"
    fi
}
