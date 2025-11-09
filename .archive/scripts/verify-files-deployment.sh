#!/usr/bin/env bash

# Verification script to check if files module deployed correctly
# Run this AFTER applying home-manager configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Expected deployments relative to $HOME
EXPECTED_FILES=(
    "bin/.env"
    "bin/bootstrap-secrets.sh"
    "bin/claudevloop"
    "bin/colorfuncs.sh"
    "bin/functions.sh"
    "bin/mkclaude_desktop_config"
    "bin/restart_claude"
    "claude/prompt/static-prompt.md"
)

verify_deployment() {
    log_info "Verifying files module deployment in $HOME"
    
    local success=true
    local missing_files=()
    local present_files=()
    
    for file in "${EXPECTED_FILES[@]}"; do
        local full_path="$HOME/$file"
        if [[ -e "$full_path" ]]; then
            present_files+=("$file")
            
            # Check if bin files are executable
            if [[ "$file" =~ ^bin/ ]] && [[ ! -x "$full_path" ]]; then
                log_warning "✓ $file (present but not executable)"
            else
                log_success "✓ $file"
            fi
        else
            missing_files+=("$file")
            log_error "✗ Missing: $file"
            success=false
        fi
    done
    
    echo
    log_info "========================================="
    log_info "DEPLOYMENT SUMMARY"
    log_info "========================================="
    log_info "Present files: ${#present_files[@]}/${#EXPECTED_FILES[@]}"
    
    if [[ "${#missing_files[@]}" -gt 0 ]]; then
        log_error "Missing files: ${#missing_files[@]}"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
    fi
    
    if $success; then
        log_success "All expected files are deployed correctly!"
        return 0
    else
        log_error "Some files are missing from deployment"
        return 1
    fi
}

check_file_sources() {
    log_info "Checking file sources and links"
    
    for file in "${EXPECTED_FILES[@]}"; do
        local full_path="$HOME/$file"
        if [[ -L "$full_path" ]]; then
            local target
            target=$(readlink "$full_path")
            if [[ "$target" =~ ^/nix/store ]]; then
                log_success "✓ $file -> $target"
            else
                log_warning "✓ $file -> $target (unexpected target)"
            fi
        elif [[ -f "$full_path" ]]; then
            log_warning "✓ $file (regular file, not symlink)"
        fi
    done
}

check_permissions() {
    log_info "Checking file permissions"
    
    for file in "${EXPECTED_FILES[@]}"; do
        local full_path="$HOME/$file"
        if [[ -e "$full_path" ]]; then
            local perms
            perms=$(stat -c "%A" "$full_path" 2>/dev/null || stat -f "%Sp" "$full_path" 2>/dev/null || echo "unknown")
            
            if [[ "$file" =~ ^bin/ ]]; then
                if [[ "$perms" =~ x ]]; then
                    log_success "✓ $file ($perms) - executable"
                else
                    log_error "✗ $file ($perms) - should be executable"
                fi
            else
                log_info "✓ $file ($perms)"
            fi
        fi
    done
}

main() {
    log_info "Files module deployment verification"
    log_info "Current directory: $(pwd)"
    log_info "Home directory: $HOME"
    echo
    
    local overall_success=true
    
    # Test 1: Verify all expected files are present
    if ! verify_deployment; then
        overall_success=false
    fi
    
    echo
    # Test 2: Check file sources (symlinks to nix store)
    check_file_sources
    
    echo
    # Test 3: Check file permissions
    check_permissions
    
    echo
    log_info "========================================="
    if $overall_success; then
        log_success "Files module verification completed successfully!"
        log_info "All expected files are properly deployed."
    else
        log_error "Files module verification found issues."
        log_info "Check the output above for details."
        exit 1
    fi
}

main "$@"
