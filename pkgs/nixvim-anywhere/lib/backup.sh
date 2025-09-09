#!/usr/bin/env bash
# backup.sh - Backup and restore functionality

create_backup() {
    local backup_id="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_dir="$BACKUP_BASE_DIR/$backup_id"
    
    log_step "Creating backup: $backup_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup in: $backup_dir"
        return 0
    fi
    
    mkdir -p "$backup_dir"
    
    # Backup existing neovim config
    if [[ -d "$HOME/.config/nvim" ]]; then
        log_info "Backing up ~/.config/nvim"
        cp -r "$HOME/.config/nvim" "$backup_dir/nvim-config"
    fi
    
    # Backup shell profiles that might have Nix in PATH
    for profile in ~/.bashrc ~/.zshrc ~/.profile ~/.bash_profile; do
        if [[ -f "$profile" ]]; then
            log_info "Backing up $profile"
            cp "$profile" "$backup_dir/$(basename "$profile")"
        fi
    done
    
    # Record system state
    cat > "$backup_dir/system-state.txt" << EOF
Backup created: $(date)
System: $(detect_system)
Existing neovim: $(which nvim 2>/dev/null || echo "none")
Existing nix: $(which nix 2>/dev/null || echo "none")
PATH: $PATH
EOF
    
    log_success "Backup created: $backup_dir"
    echo "$backup_dir"
}

# Find and collect all symlinks pointing to /nix
find_nix_symlinks() {
    local symlinks=()
    
    if command -v fd >/dev/null 2>&1; then
        # Use your preferred fd command to find nix symlinks
        while IFS= read -r line; do
            local symlink="${line% --> *}"
            local target="${line#* --> }"
            if [[ "$target" == /nix/* ]]; then
                symlinks+=("$symlink")
            fi
        done < <(fd -t l . "$HOME" -x sh -c 'printf "%s --> %s\n" "$1" "$(readlink "$1")"' sh {} 2>/dev/null)
    else
        # Fallback to find
        while IFS= read -r symlink; do
            if [[ -L "$symlink" ]]; then
                local target=$(readlink "$symlink" 2>/dev/null)
                if [[ "$target" == /nix/* ]]; then
                    symlinks+=("$symlink")
                fi
            fi
        done < <(find "$HOME" -type l 2>/dev/null)
    fi
    
    printf '%s\n' "${symlinks[@]}"
}

# Clean up remaining nix symlinks
cleanup_nix_symlinks() {
    local force_cleanup="${1:-false}"
    
    log_info "Scanning for remaining Nix symlinks..."
    local nix_symlinks=()
    while IFS= read -r symlink; do
        [[ -n "$symlink" ]] && nix_symlinks+=("$symlink")
    done < <(find_nix_symlinks)
    
    if [ ${#nix_symlinks[@]} -eq 0 ]; then
        log_success "No remaining /nix symlinks found"
        return 0
    fi
    
    log_warning "Found ${#nix_symlinks[@]} symlinks pointing to /nix:"
    for symlink in "${nix_symlinks[@]}"; do
        local target=$(readlink "$symlink" 2>/dev/null || echo "broken")
        echo "  $symlink --> $target"
    done
    
    if [[ "$force_cleanup" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove ${#nix_symlinks[@]} symlinks"
            return 0
        fi
        
        log_info "Removing ${#nix_symlinks[@]} remaining Nix symlinks..."
        for symlink in "${nix_symlinks[@]}"; do
            if [[ -L "$symlink" ]]; then
                log_info "Removing symlink: $symlink"
                rm -f "$symlink" || log_warning "Failed to remove: $symlink"
            fi
        done
        log_success "Cleanup complete"
    else
        echo
        read -p "Remove these symlinks automatically? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing ${#nix_symlinks[@]} Nix symlinks..."
            for symlink in "${nix_symlinks[@]}"; do
                if [[ -L "$symlink" ]]; then
                    log_info "Removing symlink: $symlink"
                    rm -f "$symlink" || log_warning "Failed to remove: $symlink"
                fi
            done
            log_success "Symlink cleanup complete"
        else
            log_warning "Symlinks left in place. You can remove them manually or re-run uninstall."
        fi
    fi
}

perform_rollback() {
    log_step "Rolling back to pre-Nix state"
    
    # Skip interactive prompts if no backups (idempotent behavior)
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_warning "No backups found in $BACKUP_BASE_DIR - proceeding with cleanup only"
    else
        # Find most recent backup
        local latest_backup=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_*" 2>/dev/null | sort | tail -1)
        
        if [[ -n "$latest_backup" ]]; then
            log_warning "This will restore system to state before nixvim-anywhere installation"
            log_info "Using backup: $latest_backup"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would restore from: $latest_backup"
            else
                read -p "Are you sure you want to rollback? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Rollback cancelled - proceeding with cleanup only"
                else
                    # Find all backup files created by home-manager
                    log_info "Discovering backup files..."
                    local backup_files=()
                    while IFS= read -r backup_file; do
                        backup_files+=("$backup_file")
                    done < <(fd -t f '\.backup-by-nixvim-anywhere$' "$HOME" --max-depth 3 2>/dev/null || find "$HOME" -maxdepth 3 -name "*.backup-by-nixvim-anywhere" -type f 2>/dev/null)
                    
                    if [ ${#backup_files[@]} -eq 0 ]; then
                        log_warning "No .backup-by-nixvim-anywhere files found from home-manager"
                        log_info "Checking nixvim-anywhere backup directory instead..."
                        
                        # Fallback to nixvim-anywhere backup directory
                        if [[ -d "$latest_backup" ]]; then
                            log_info "Restoring from nixvim-anywhere backup: $latest_backup"
                            # Restore neovim config
                            if [[ -d "$latest_backup/nvim-config" ]]; then
                                log_info "Restoring neovim configuration..."
                                rm -rf "$HOME/.config/nvim"
                                cp -r "$latest_backup/nvim-config" "$HOME/.config/nvim"
                            fi
                        fi
                    else
                        log_info "Found ${#backup_files[@]} backup files to restore"
                        
                        # Restore each backup file
                        for backup_file in "${backup_files[@]}"; do
                            local original_file="${backup_file%.backup-by-nixvim-anywhere}"
                            local relative_path="${original_file#$HOME/}"
                            
                            # Remove existing file/symlink
                            if [[ -e "$original_file" || -L "$original_file" ]]; then
                                log_info "Removing existing: ~/$relative_path"
                                rm -f "$original_file"
                            fi
                            
                            # Restore from backup
                            log_info "Restoring: ~/$relative_path"
                            cp "$backup_file" "$original_file"
                        done
                    fi
                fi
            fi
        fi
    fi
    
    # Always perform cleanup (idempotent)
    log_info "Removing Nix installation..."
    if pgrep nix-daemon >/dev/null 2>&1; then
        log_info "Stopping Nix daemon..."
        sudo pkill nix-daemon || true
    fi
    
    if [[ -d "/nix" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove /nix directory"
        else
            sudo rm -rf /nix || {
                log_warning "Failed to remove /nix directory automatically"
                log_info "You may need to manually run: sudo rm -rf /nix"
            }
        fi
    fi
    
    # Remove user Nix files (idempotent)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove ~/.nix-* files"
    else
        rm -rf ~/.nix-* || true
    fi
    
    # Remove home-manager config (idempotent)
    if [[ -d "$HOME/.config/home-manager" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove ~/.config/home-manager"
        else
            rm -rf "$HOME/.config/home-manager"
        fi
    fi
    
    if [[ -f "$HOME/.nix-channels" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove ~/.nix-channels"
        else
            rm -f "$HOME/.nix-channels"
        fi
    fi
    
    log_success "System rollback complete!"
    echo
    log_info "Restart your shell to complete restoration: exec \$SHELL"
}

perform_uninstall() {
    log_step "Uninstalling Nix and home-manager"

    # Attempt automatic rollback first
    log_info "Attempting to restore from backups..."
    perform_rollback

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform final cleanup and symlink removal"
        cleanup_nix_symlinks true
        return 0
    fi
    
    # Final cleanup of any remaining symlinks
    cleanup_nix_symlinks
    
    log_success "Nix uninstallation complete!"
    echo
    log_info "Restart your shell to complete cleanup: exec \$SHELL"
}
