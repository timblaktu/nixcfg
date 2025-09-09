#!/usr/bin/env bash
# nix.sh - Nix installation and home-manager setup

install_nix() {
    log_step "Installing Nix (single-user mode)"
    
    if command -v nix >/dev/null 2>&1; then
        log_success "Nix already installed"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install Nix with: curl -L https://nixos.org/nix/install | sh -s -- --no-daemon"
        return 0
    fi
    
    # Install Nix in single-user mode (no daemon, safer)
    log_info "Downloading and installing Nix..."
    if ! curl -L https://nixos.org/nix/install | sh -s -- --no-daemon; then
        log_error "Nix installation failed"
        return 1
    fi
    
    # Source Nix environment
    if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        source "$HOME/.nix-profile/etc/profile.d/nix.sh"
        log_success "Nix installed and loaded"
    else
        log_error "Nix installation completed but profile not found"
        return 1
    fi
    
    # Add Nix to shell initialization
    configure_shell_integration
    
    # Verify installation
    if command -v nix >/dev/null 2>&1; then
        log_success "Nix installation verified"
        nix --version
    else
        log_error "Nix installation verification failed"
        return 1
    fi
}

configure_shell_integration() {
    log_step "Configuring shell integration"
    
    local nix_source_line='source ~/.nix-profile/etc/profile.d/nix.sh'
    local shell_config=""
    
    # Detect current shell and appropriate config file
    if [[ "$SHELL" == */bash ]] || [[ "$SHELL" == */sh ]]; then
        shell_config="$HOME/.bashrc"
    elif [[ "$SHELL" == */zsh ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ "$SHELL" == */fish ]]; then
        # Fish has different syntax
        nix_source_line='if test -e ~/.nix-profile/etc/profile.d/nix.fish; source ~/.nix-profile/etc/profile.d/nix.fish; end'
        shell_config="$HOME/.config/fish/config.fish"
        # Ensure fish config directory exists
        mkdir -p "$(dirname "$shell_config")"
    else
        log_warn "Unknown shell: $SHELL, defaulting to .bashrc"
        shell_config="$HOME/.bashrc"
    fi
    
    # Check if already configured
    if [[ -f "$shell_config" ]] && grep -q "nix-profile/etc/profile.d/nix" "$shell_config"; then
        log_success "Nix already configured in $shell_config"
        return 0
    fi
    
    # Add source line to shell config
    log_info "Adding Nix source to $shell_config"
    echo "" >> "$shell_config"
    echo "# Added by nixvim-anywhere" >> "$shell_config"
    echo "$nix_source_line" >> "$shell_config"
    
    log_success "Nix integration added to $shell_config"
    log_info "Restart your shell or run: source $shell_config"
}

configure_nix_settings() {
    log_step "Configuring Nix experimental features"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Nix with experimental features: nix-command flakes"
        return 0
    fi
    
    # Ensure Nix is available
    if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        source "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    # Set experimental features via environment variable
    log_info "Setting experimental features via environment: nix-command flakes"
    export NIX_CONFIG="experimental-features = nix-command flakes"
    
    log_success "Nix configuration applied via environment"
}

install_home_manager() {
    log_step "Setting up home-manager"
    
    if command -v home-manager >/dev/null 2>&1; then
        log_success "home-manager already available"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install home-manager"
        return 0
    fi
    
    # Ensure Nix is available
    if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        source "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    # Add home-manager channel
    log_info "Adding home-manager channel..."
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    nix-channel --update
    
    # Install home-manager
    log_info "Installing home-manager..."
    nix-shell '<home-manager>' -A install
    
    # Verify installation
    if command -v home-manager >/dev/null 2>&1; then
        log_success "home-manager installed successfully"
        home-manager --version
    else
        log_error "home-manager installation failed"
        return 1
    fi
}

create_home_manager_config() {
    log_step "Configuring home-manager to use nixcfg flake"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure home-manager to use flake: $CONFIG_TARGET"
        return 0
    fi
    
    # Verify nixcfg directory exists
    local nixcfg_path="$HOME/src/nixcfg"
    if [[ ! -d "$nixcfg_path" ]]; then
        log_error "nixcfg directory not found at $nixcfg_path"
        log_info "Please clone your nixcfg repository to $nixcfg_path"
        return 1
    fi
    
    log_success "Using existing nixcfg flake configuration"
    log_info "Configuration target: $CONFIG_TARGET"
    log_info "Flake path: $nixcfg_path"
}

apply_home_manager_config() {
    log_step "Applying home-manager configuration from nixcfg flake"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: cd $HOME/src/nixcfg && NIX_CONFIG='experimental-features = nix-command flakes' home-manager switch --flake '.#$CONFIG_TARGET' -b backup-by-nixvim-anywhere"
        return 0
    fi
    
    # Ensure environment is loaded
    if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        source "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    # Apply configuration using flake with environment NIX_CONFIG
    log_info "Running home-manager switch with flake configuration..."
    cd "$HOME/src/nixcfg"
    if NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --flake ".#$CONFIG_TARGET" -b backup-by-nixvim-anywhere; then
        log_success "home-manager configuration applied successfully"
    else
        log_error "home-manager switch failed"
        return 1
    fi
}
