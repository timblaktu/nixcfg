#!/usr/bin/env bash
# test-nixvim-anywhere.sh
# Comprehensive test suite for nixvim-anywhere implementation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TEST_LOG="/tmp/nixvim-anywhere-test-$TEST_TIMESTAMP.log"

# Colors and output functions
red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }
bold() { echo -e "\033[1m$*\033[0m"; }

log_info() { echo "ℹ️  $*" | tee -a "$TEST_LOG"; }
log_success() { green "✅ $*" | tee -a "$TEST_LOG"; }
log_warning() { yellow "⚠️  $*" | tee -a "$TEST_LOG"; }
log_error() { red "❌ $*" | tee -a "$TEST_LOG"; }
log_step() { blue "🔧 $*" | tee -a "$TEST_LOG"; }

print_header() {
    bold "=== nixvim-anywhere Test Suite ===" | tee -a "$TEST_LOG"
    echo "Testing nixvim-anywhere implementation and integration" | tee -a "$TEST_LOG"
    echo "Test log: $TEST_LOG" | tee -a "$TEST_LOG"
    echo | tee -a "$TEST_LOG"
}

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    log_step "Test $TESTS_TOTAL: $test_name"
    
    if eval "$test_command" 2>&1 | tee -a "$TEST_LOG"; then
        log_success "PASSED: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "FAILED: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_package_structure() {
    log_info "Checking nixvim-anywhere package structure..."
    
    # Check if main files exist
    local required_files=(
        "README.md"
        "default.nix"
        "nixvim-anywhere"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            echo "Missing required file: $file"
            return 1
        fi
    done
    
    echo "All required files present"
    return 0
}

test_nix_package_build() {
    log_info "Testing Nix package build..."
    
    cd "$SCRIPT_DIR/../.."  # Go to nixcfg root
    
    # Test that the package builds without errors
    if nix build ".#nixvim-anywhere" --no-link; then
        echo "Base package builds successfully"
    else
        echo "Base package build failed"
        return 1
    fi
    
    # Test convenience targets
    for target in "nixvim-anywhere-tblack-t14" "nixvim-anywhere-mbp"; do
        if nix build ".#$target" --no-link; then
            echo "Target $target builds successfully"
        else
            echo "Target $target build failed"
            return 1
        fi
    done
    
    return 0
}

test_script_syntax() {
    log_info "Testing script syntax..."
    
    # Test main script syntax
    if bash -n "$SCRIPT_DIR/nixvim-anywhere"; then
        echo "Main script syntax valid"
    else
        echo "Main script syntax errors"
        return 1
    fi
    
    # Test web installer syntax  
    if bash -n "$SCRIPT_DIR/../../install-nixvim-anywhere.sh"; then
        echo "Web installer syntax valid"
    else
        echo "Web installer syntax errors"
        return 1
    fi
    
    return 0
}

test_package_outputs() {
    log_info "Testing package outputs..."
    
    cd "$SCRIPT_DIR/../.."
    local package_path
    package_path=$(nix build ".#nixvim-anywhere-tblack-t14" --no-link --print-out-paths)
    
    # Check expected output structure
    local expected_files=(
        "bin/nixvim-anywhere"
        "share/nixvim-anywhere/home-manager-template.nix"
        "share/nixvim-anywhere/install-nixvim-anywhere.sh"
        "share/doc/nixvim-anywhere/README.md"
        "share/doc/nixvim-anywhere/QUICKSTART.md"
        "share/nixvim-anywhere/version.txt"
    )
    
    for file in "${expected_files[@]}"; do
        if [[ ! -f "$package_path/$file" ]]; then
            echo "Missing output file: $file"
            return 1
        fi
    done
    
    # Check that main script is executable
    if [[ ! -x "$package_path/bin/nixvim-anywhere" ]]; then
        echo "Main script not executable"
        return 1
    fi
    
    echo "All expected output files present and correctly structured"
    return 0
}

test_flake_integration() {
    log_info "Testing flake integration..."
    
    cd "$SCRIPT_DIR/../.."
    
    # Test that packages are exposed in flake
    local packages_output
    packages_output=$(nix flake show --json . 2>/dev/null | grep -o '"nixvim-anywhere[^"]*"' || echo "")
    
    if [[ -z "$packages_output" ]]; then
        echo "nixvim-anywhere packages not found in flake outputs"
        return 1
    fi
    
    echo "nixvim-anywhere packages properly exposed in flake"
    return 0
}

test_help_functionality() {
    log_info "Testing help functionality..."
    
    cd "$SCRIPT_DIR/../.."
    local package_path
    package_path=$(nix build ".#nixvim-anywhere" --no-link --print-out-paths)
    
    # Test help output
    if "$package_path/bin/nixvim-anywhere" help >/dev/null 2>&1; then
        echo "Help functionality works"
        return 0
    else
        echo "Help functionality failed"
        return 1
    fi
}

test_dry_run_functionality() {
    log_info "Testing dry-run functionality..."
    
    cd "$SCRIPT_DIR/../.."
    local package_path
    package_path=$(nix build ".#nixvim-anywhere" --no-link --print-out-paths)
    
    # Test dry-run mode (should not make any changes)
    if DRY_RUN=true "$package_path/bin/nixvim-anywhere" install --dry-run --backup 2>/dev/null; then
        echo "Dry-run mode works"
        return 0
    else
        echo "Dry-run mode failed"
        return 1
    fi
}

test_documentation_quality() {
    log_info "Testing documentation quality..."
    
    # Check that documentation files are not empty and contain key sections
    local docs=(
        "$SCRIPT_DIR/README.md"
    )
    
    for doc in "${docs[@]}"; do
        if [[ ! -s "$doc" ]]; then
            echo "Documentation file is empty: $doc"
            return 1
        fi
        
        # Check for key sections in README
        if [[ "$doc" == *"README.md" ]]; then
            if ! grep -q "Quick Start" "$doc"; then
                echo "README missing Quick Start section"
                return 1
            fi
            if ! grep -q "Philosophy" "$doc"; then
                echo "README missing Philosophy section"  
                return 1
            fi
        fi
    done
    
    echo "Documentation quality checks passed"
    return 0
}

test_web_installer() {
    log_info "Testing web installer..."
    
    # Test that web installer can show help without network
    if bash "$SCRIPT_DIR/../../install-nixvim-anywhere.sh" --help >/dev/null 2>&1; then
        echo "Web installer help works"
    else
        echo "Web installer help failed"
        return 1
    fi
    
    # Check for key safety warnings in installer
    if grep -q "warn_about_changes" "$SCRIPT_DIR/../../install-nixvim-anywhere.sh"; then
        echo "Web installer includes safety warnings"
    else
        echo "Web installer missing safety warnings"
        return 1
    fi
    
    return 0
}

test_template_validity() {
    log_info "Testing home-manager template validity..."
    
    cd "$SCRIPT_DIR/../.."
    local package_path
    package_path=$(nix build ".#nixvim-anywhere" --no-link --print-out-paths)
    
    local template="$package_path/share/nixvim-anywhere/home-manager-template.nix"
    
    # Test that template has valid Nix syntax
    if nix-instantiate --parse "$template" >/dev/null 2>&1; then
        echo "home-manager template has valid syntax"
    else
        echo "home-manager template syntax error"
        return 1
    fi
    
    # Check that template contains required sections
    if grep -q "programs.nixvim" "$template"; then
        echo "Template contains nixvim configuration"
    else
        echo "Template missing nixvim configuration"
        return 1
    fi
    
    return 0
}

run_all_tests() {
    print_header
    
    # Run all test categories
    run_test "Package Structure" "test_package_structure"
    run_test "Nix Package Build" "test_nix_package_build"  
    run_test "Script Syntax" "test_script_syntax"
    run_test "Package Outputs" "test_package_outputs"
    run_test "Flake Integration" "test_flake_integration"
    run_test "Help Functionality" "test_help_functionality"
    run_test "Dry-run Functionality" "test_dry_run_functionality"
    run_test "Documentation Quality" "test_documentation_quality"
    run_test "Web Installer" "test_web_installer"
    run_test "Template Validity" "test_template_validity"
    
    # Print summary
    echo | tee -a "$TEST_LOG"
    bold "=== Test Summary ===" | tee -a "$TEST_LOG"
    echo "Total tests: $TESTS_TOTAL" | tee -a "$TEST_LOG"
    log_success "Passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Failed: $TESTS_FAILED"
    else
        echo "Failed: $TESTS_FAILED" | tee -a "$TEST_LOG"
    fi
    echo | tee -a "$TEST_LOG"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "🎉 All tests passed! nixvim-anywhere is ready for production."
        echo | tee -a "$TEST_LOG"
        echo "Next steps:" | tee -a "$TEST_LOG"
        echo "1. Test deployment on a real Type 3 system" | tee -a "$TEST_LOG"
        echo "2. Validate end-to-end functionality" | tee -a "$TEST_LOG"
        echo "3. Deploy to production or share with users" | tee -a "$TEST_LOG"
        return 0
    else
        log_error "Some tests failed. Review the errors above before proceeding."
        echo "Test log: $TEST_LOG" | tee -a "$TEST_LOG"
        return 1
    fi
}

# Handle command line arguments
case "${1:-all}" in
    all)
        run_all_tests
        ;;
    build)
        run_test "Package Build" "test_nix_package_build"
        ;;
    syntax)
        run_test "Script Syntax" "test_script_syntax"
        ;;
    integration)
        run_test "Flake Integration" "test_flake_integration"
        ;;
    help|--help|-h)
        echo "nixvim-anywhere Test Suite"
        echo
        echo "Usage: $0 [test-category]"
        echo
        echo "Test categories:"
        echo "  all         Run all tests (default)"
        echo "  build       Test package building"
        echo "  syntax      Test script syntax"
        echo "  integration Test flake integration"
        echo "  help        Show this help"
        echo
        ;;
    *)
        log_error "Unknown test category: $1"
        echo "Use 'help' for available options"
        exit 1
        ;;
esac
