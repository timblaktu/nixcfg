#!/usr/bin/env bash
# Make script executable
chmod +x "$0" 2>/dev/null || true

# Test script for home/modules/files module functionality
# Tests file deployment across different platforms and configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test configurations to validate
CONFIGS=(
    "tim@thinky-ubuntu"
    "tim@thinky-nixos" 
    "tim@tblack-t14-nixos"
    "tim@mbp"
    "tim@potato"
)

# Expected file deployments based on home/files structure
EXPECTED_BIN_FILES=(
    "bin/.env"
    "bin/bootstrap-secrets.sh"
    "bin/claudevloop"
    "bin/colorfuncs.sh"
    "bin/functions.sh"
    "bin/mkclaude_desktop_config"
    "bin/restart_claude"
)

EXPECTED_CLAUDE_FILES=(
    "claude"  # Recursive directory entry
)

# Test functions
test_config_build() {
    local config=$1
    log_info "Testing build for configuration: $config"
    
    if nix build ".#homeConfigurations.\"$config\".activationPackage" --no-link --quiet 2>/dev/null; then
        log_success "Build successful for $config"
        return 0
    else
        log_error "Build failed for $config"
        return 1
    fi
}

test_config_evaluation() {
    local config=$1
    log_info "Testing evaluation for configuration: $config"
    
    if nix eval ".#homeConfigurations.\"$config\".config.home.file" --json --quiet >/dev/null 2>&1; then
        log_success "Evaluation successful for $config"
        return 0
    else
        log_error "Evaluation failed for $config"
        return 1
    fi
}

check_file_deployments() {
    local config=$1
    log_info "Checking file deployments for: $config"
    
    # Get the home.file configuration as JSON
    local home_files
    if ! home_files=$(nix eval ".#homeConfigurations.\"$config\".config.home.file" --json 2>/dev/null); then
        log_error "Failed to evaluate home.file for $config"
        return 1
    fi
    
    local success=true
    
    # Check bin files
    for file in "${EXPECTED_BIN_FILES[@]}"; do
        if echo "$home_files" | jq -e "has(\"$file\")" >/dev/null 2>&1; then
            # Check if executable is set for bin files
            local executable
            executable=$(echo "$home_files" | jq -r ".\"$file\".executable // false")
            if [[ "$executable" == "true" ]]; then
                log_success "✓ $file (executable)"
            else
                log_warning "✓ $file (not executable - potential issue)"
                success=false
            fi
        else
            log_error "✗ Missing: $file"
            success=false
        fi
    done
    
    # Check claude files
    for file in "${EXPECTED_CLAUDE_FILES[@]}"; do
        if echo "$home_files" | jq -e ".\"$file\"" >/dev/null 2>&1; then
            # Check if it's properly configured as recursive
            local recursive
            recursive=$(echo "$home_files" | jq -r ".\"$file\".recursive // false")
            if [[ "$recursive" == "true" ]]; then
                log_success "✓ $file (recursive directory)"
            else
                log_warning "✓ $file (not recursive - potential issue)"
                success=false
            fi
        else
            log_error "✗ Missing: $file"
            success=false
        fi
    done
    
    # Check for unexpected .config deployments (should be empty)
    local config_files
    config_files=$(echo "$home_files" | jq -r 'keys[]' | grep "^\.config/" | wc -l)
    if [[ "$config_files" -eq 0 ]]; then
        log_success "✓ No unexpected .config files (config/ directory is empty)"
    else
        log_warning "Found $config_files .config files (unexpected since config/ is empty)"
    fi
    
    if $success; then
        return 0
    else
        return 1
    fi
}

test_file_permissions() {
    local config=$1
    log_info "Testing file permissions for: $config"
    
    local home_files
    if ! home_files=$(nix eval ".#homeConfigurations.\"$config\".config.home.file" --json 2>/dev/null); then
        log_error "Failed to evaluate home.file for $config"
        return 1
    fi
    
    # Check that bin files are executable
    local bin_executable_count
    bin_executable_count=$(echo "$home_files" | jq '[.[] | select(.executable == true)] | length')
    
    if [[ "$bin_executable_count" -eq "${#EXPECTED_BIN_FILES[@]}" ]]; then
        log_success "All bin files are marked executable"
        return 0
    else
        log_error "Expected ${#EXPECTED_BIN_FILES[@]} executable files, found $bin_executable_count"
        return 1
    fi
}

test_source_paths() {
    local config=$1
    log_info "Testing source paths for: $config"
    
    local home_files
    if ! home_files=$(nix eval ".#homeConfigurations.\"$config\".config.home.file" --json 2>/dev/null); then
        log_error "Failed to evaluate home.file for $config"
        return 1
    fi
    
    # Check that source paths are correct for our files module outputs only
    local invalid_sources=()
    while IFS= read -r source_path; do
        if [[ ! "$source_path" =~ ^/nix/store/.*/source/home/files/ ]]; then
            invalid_sources+=("$source_path")
        fi
    done < <(echo "$home_files" | jq -r '.[] | select(.source | test("/home/files/")) | .source')
    
    if [[ "${#invalid_sources[@]}" -eq 0 ]]; then
        log_success "All source paths are valid"
        return 0
    else
        log_error "Found invalid source paths:"
        printf '%s\n' "${invalid_sources[@]}"
        return 1
    fi
}

run_platform_tests() {
    local config=$1
    local platform_success=true
    
    echo
    log_info "========================================="
    log_info "Testing configuration: $config"
    log_info "========================================="
    
    # Test 1: Configuration builds successfully
    if ! test_config_build "$config"; then
        platform_success=false
    fi
    
    # Test 2: Configuration evaluates without errors
    if ! test_config_evaluation "$config"; then
        platform_success=false
    fi
    
    # Test 3: Expected files are deployed
    if ! check_file_deployments "$config"; then
        platform_success=false
    fi
    
    # Test 4: File permissions are correct
    if ! test_file_permissions "$config"; then
        platform_success=false
    fi
    
    # Test 5: Source paths are valid
    if ! test_source_paths "$config"; then
        platform_success=false
    fi
    
    if $platform_success; then
        log_success "All tests passed for $config"
        return 0
    else
        log_error "Some tests failed for $config"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting files module tests across platforms"
    log_info "Testing ${#CONFIGS[@]} configurations..."
    
    local overall_success=true
    local failed_configs=()
    
    # Check if we're in the right directory
    if [[ ! -f "flake.nix" ]]; then
        log_error "Must be run from the nixcfg directory"
        exit 1
    fi
    
    # Run tests for each configuration
    for config in "${CONFIGS[@]}"; do
        if ! run_platform_tests "$config"; then
            overall_success=false
            failed_configs+=("$config")
        fi
    done
    
    # Summary
    echo
    log_info "========================================="
    log_info "TEST SUMMARY"
    log_info "========================================="
    
    if $overall_success; then
        log_success "All configurations passed all tests!"
        log_info "The files module is working correctly across all platforms."
    else
        log_error "Some configurations failed tests:"
        for config in "${failed_configs[@]}"; do
            log_error "  - $config"
        done
        log_info "Review the output above for specific issues."
        exit 1
    fi
}

# Check dependencies
if ! command -v nix >/dev/null 2>&1; then
    log_error "nix command not found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq command not found (required for JSON parsing)"
    exit 1
fi

# Run main function
main "$@"
