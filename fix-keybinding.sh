#!/bin/bash
# Script to fix the <leader>f keybinding conflict in nixvim

echo "Fixing nixvim keybinding conflict..."
echo "Changing LSP format from <leader>f to <leader>lf"

# Backup the original file
cp /home/tim/src/nixcfg/home/common/nixvim.nix /home/tim/src/nixcfg/home/common/nixvim.nix.bak

# Fix the keybinding
sed -i 's/"<leader>f" = "format";/"<leader>lf" = "format";  # Changed from <leader>f to avoid Telescope conflict/' /home/tim/src/nixcfg/home/common/nixvim.nix

echo "Done! Changes made:"
echo "  - LSP format: <leader>f → <leader>lf (Space+l+f)"
echo "  - Telescope commands remain unchanged (Space+f+f, Space+f+g, etc.)"
echo ""
echo "To apply: Run 'home-manager switch' or rebuild your nix config"
echo "Backup saved to: nixvim.nix.bak"
