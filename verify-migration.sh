#!/usr/bin/env bash

# Flake-Parts Migration Verification Script
# This script helps verify that the flake-parts migration was successful

set -e

echo "🔍 Verifying flake-parts migration..."
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if flake-parts is properly configured
echo "📋 Basic Structure Checks"
echo "========================"

# Check flake.nix contains flake-parts
if grep -q "flake-parts" flake.nix; then
    print_status 0 "flake-parts is configured as input"
else
    print_status 1 "flake-parts not found in flake.nix"
fi

# Check modular structure exists
if [ -d "flake-modules" ]; then
    print_status 0 "flake-modules directory exists"
    
    # Check individual modules
    modules=("systems.nix" "overlays.nix" "packages.nix" "dev-shells.nix" "nixos-configurations.nix" "darwin-configurations.nix" "home-configurations.nix")
    
    for module in "${modules[@]}"; do
        if [ -f "flake-modules/$module" ]; then
            print_status 0 "Module flake-modules/$module exists"
        else
            print_status 1 "Module flake-modules/$module missing"
        fi
    done
else
    print_status 1 "flake-modules directory not found"
fi

echo
echo "🧪 Flake Validation"
echo "===================="

# Test flake check
print_info "Running nix flake check..."
if nix flake check --no-build 2>/dev/null; then
    print_status 0 "Flake structure is valid"
else
    print_status 1 "Flake check failed - there may be syntax errors"
    echo "Run 'nix flake check' manually to see detailed errors"
fi

# Test flake show
print_info "Checking flake outputs..."
if nix flake show . --no-build 2>/dev/null >/dev/null; then
    print_status 0 "Flake outputs are accessible"
else
    print_status 1 "Cannot access flake outputs"
fi

echo
echo "📦 Configuration Availability"
echo "=============================="

# Check that key configurations exist
print_info "Checking NixOS configurations..."
for config in "mbp" "potato" "thinky-nixos" "tblack-t14-nixos"; do
    if nix eval ".#nixosConfigurations.$config.config.system.name" 2>/dev/null >/dev/null; then
        print_status 0 "NixOS config '$config' is accessible"
    else
        print_status 1 "NixOS config '$config' has issues"
    fi
done

print_info "Checking Home Manager configurations..."
for config in "tim@mbp" "tim@thinky-nixos" "tim@tblack-t14-nixos" "tim@nixvim-minimal"; do
    if nix eval ".#homeConfigurations.\"$config\".config.home.homeDirectory" 2>/dev/null >/dev/null; then
        print_status 0 "Home config '$config' is accessible"
    else
        print_status 1 "Home config '$config' has issues"
    fi
done

echo
echo "🛠️  Development Environment"
echo "=========================="

# Test development shell
print_info "Testing development shell..."
if nix develop --command echo "Development shell works" 2>/dev/null >/dev/null; then
    print_status 0 "Development shell is functional"
else
    print_status 1 "Development shell has issues"
fi

# Test custom packages
print_info "Testing custom packages..."
if nix eval ".#packages.x86_64-linux.nixvim-anywhere" 2>/dev/null >/dev/null; then
    print_status 0 "Custom packages are accessible"
else
    print_status 1 "Custom packages have issues"
fi

echo
echo "📊 Migration Summary"
echo "===================="

# Count lines of code reduction
if [ -f "flake.old" ]; then
    old_lines=$(wc -l < flake.old)
    new_lines=$(wc -l < flake.nix)
    reduction=$((old_lines - new_lines))
    print_info "flake.nix size reduction: $old_lines → $new_lines lines (-$reduction lines)"
fi

# Count number of modules
module_count=$(find flake-modules -name "*.nix" | wc -l)
print_info "Number of flake modules: $module_count"

echo
echo "🎯 Next Steps"
echo "============="
echo "1. Test a configuration deployment:"
echo "   nix run home-manager -- switch --flake .#tim@tblack-t14-nixos --dry-run"
echo
echo "2. If everything looks good, remove backup files:"
echo "   rm flake.old  # (if you don't need the old version)"
echo
echo "3. Check out the new features:"
echo "   nix run .#check    # Quick flake validation"
echo "   nix run .#update   # Update flake inputs"
echo
echo "4. Read the documentation:"
echo "   cat FLAKE-PARTS-MIGRATION.md"
echo "   cat MIGRATION-CHECKLIST.md"

print_info "Migration verification complete! 🚀"
