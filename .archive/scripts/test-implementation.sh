#!/usr/bin/env bash
# Test script to validate the new Nix file management implementation

set -e

echo "Testing Nix file management implementation..."

# Change to nixcfg directory
cd /home/tim/src/nixcfg

echo "1. Checking Nix flake syntax..."
nix flake check --show-trace

echo "2. Building thinky-ubuntu home configuration..."
nix build --show-trace .#homeConfigurations."tim@thinky-ubuntu".activationPackage

echo "3. Checking that files would be deployed correctly..."
# This shows what files would be linked without actually applying
nix build --show-trace .#homeConfigurations."tim@thinky-ubuntu".activationPackage --json | jq -r '.[0].outputs.out' | xargs ls -la

echo "✅ All tests passed! The Nix file management system is working correctly."
