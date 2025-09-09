#!/usr/bin/env bash

# Quick diagnostic for files module
set -euo pipefail

cd /home/tim/src/nixcfg

echo "Testing files module diagnostics..."

echo
echo "1. Checking if files directory exists:"
ls -la home/files/

echo
echo "2. Testing basic evaluation:"
if nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json >/dev/null 2>&1; then
    echo "✓ Configuration evaluates successfully"
else
    echo "✗ Configuration evaluation failed"
    exit 1
fi

echo
echo "3. Checking for any bin/ entries in home.file:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | grep "^bin/" | sort || echo "No bin/ entries found"

echo
echo "4. Checking for any claude/ entries in home.file:"  
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | grep "^claude/" | head -5 || echo "No claude/ entries found"

echo
echo "5. Total home.file entries:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq 'keys | length'

echo
echo "6. Sample home.file entries:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | head -10

echo
echo "7. Checking .env file specifically (using hasAttr):"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq 'has("bin/.env")'

echo
echo "8. Checking restart_claude file specifically:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq '."bin/restart_claude"' || echo "bin/restart_claude not found"
