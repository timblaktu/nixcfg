#!/bin/bash

# Source the workspace script functions
source ./workspace

echo "Testing parse_flake_inputs function:"
parse_flake_inputs flake.nix | grep home-manager

echo -e "\nTesting get_flake_input_url function:"
current_url=$(get_flake_input_url home-manager upstream)
echo "Current URL for home-manager in upstream workspace: '$current_url'"

# Test direct parsing
echo -e "\nDirect grep test:"
grep -A 2 "home-manager.*=" flake.nix