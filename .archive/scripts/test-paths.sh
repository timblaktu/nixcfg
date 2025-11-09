#!/usr/bin/env bash

# Test path resolution in the files module
set -euo pipefail

cd /home/tim/src/nixcfg

echo "Testing path resolution for files module..."

echo
echo "1. Testing direct path evaluation:"
nix eval --impure --expr "builtins.pathExists ./home/files"

echo
echo "2. Testing from module context (home/modules/files/):"
nix eval --impure --expr "let filesDir = ./home/files; in builtins.pathExists filesDir"

echo  
echo "3. Testing relative path from module location:"
cd home/modules/files
nix eval --impure --expr "builtins.pathExists ./../../files"

echo
echo "4. Testing absolute path approach:"
cd /home/tim/src/nixcfg
nix eval --impure --expr "let filesDir = ./home/files + \"/bin\"; in builtins.pathExists filesDir"

echo
echo "5. Testing what the module actually sees:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config --json 2>/dev/null | jq '.home.file | keys[]' | grep -E "(bin|claude)" || echo "No matching entries found"
