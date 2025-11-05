#!/bin/bash

set -euo pipefail

# Test the URL extraction logic
echo "=== Testing URL extraction logic ==="

# Create a temp file with our flake content
temp_file=$(mktemp)
cp flake.nix "$temp_file"

echo "1. Testing parse_flake_inputs:"
./workspace config show-flake-inputs upstream | grep "home-manager"

echo -e "\n2. Testing current URL extraction:"
current_url=$(awk '
        BEGIN { 
            in_inputs = 0
            current_input = ""
            brace_depth = 0
        }
        
        # Start of inputs section
        /inputs\s*=\s*{/ { 
            in_inputs = 1
            brace_depth = 1
            next 
        }
        
        # Track brace depth to handle nested structures
        in_inputs && /{/ { brace_depth++ }
        in_inputs && /}/ { 
            brace_depth--
            if (brace_depth == 0) {
                in_inputs = 0
            }
            if (current_input != "" && brace_depth == 1) {
                current_input = ""  # End of current input block
            }
            next
        }
        
        # Simple format: input.url = "url"
        in_inputs && brace_depth == 1 && /^[[:space:]]*[a-zA-Z0-9_-]+\.url[[:space:]]*=/ {
            gsub(/^[[:space:]]+/, "")  # Remove leading whitespace
            gsub(/;.*$/, "")           # Remove trailing semicolon and comments
            if (match($0, /^([a-zA-Z0-9_-]+)\.url[[:space:]]*=[[:space:]]*"([^"]+)"/, arr)) {
                print arr[1] " " arr[2]
            }
            next
        }
        
        # Complex format start: input = {
        in_inputs && brace_depth == 1 && /^[[:space:]]*[a-zA-Z0-9_-]+[[:space:]]*=/ && /{/ {
            gsub(/^[[:space:]]+/, "")
            if (match($0, /^([a-zA-Z0-9_-]+)[[:space:]]*=/, arr)) {
                current_input = arr[1]
            }
            next
        }
        
        # Complex format URL line: url = "url";
        in_inputs && brace_depth == 2 && current_input != "" && /^[[:space:]]*url[[:space:]]*=/ {
            gsub(/^[[:space:]]+/, "")  # Remove leading whitespace
            gsub(/;.*$/, "")           # Remove trailing semicolon and comments
            if (match($0, /^url[[:space:]]*=[[:space:]]*"([^"]+)"/, arr)) {
                print current_input " " arr[1]
            }
            next
        }
    ' "$temp_file" | grep "^home-manager " | cut -d' ' -f2-)
echo "Extracted current URL: '$current_url'"

echo -e "\n3. Testing override URL:"
override_url=$(cd worktrees/upstream 2>/dev/null && git config --worktree --get "workspace.flake.input.home-manager.url" 2>/dev/null || true)
echo "Override URL: '$override_url'"

echo -e "\n4. Testing the binary directly:"
flake_modifier_binary="./flake-input-modifier/target/debug/flake-input-modifier"
if [[ -x "$flake_modifier_binary" ]]; then
    echo "Binary found and executable"
    echo "Current URL: '$current_url'"
    echo "Override URL: '$override_url'"
    
    if [[ -n "$current_url" && -n "$override_url" ]]; then
        echo "Testing replacement:"
        "$flake_modifier_binary" "$temp_file" home-manager "$current_url" "$override_url" | grep -A 3 "home-manager"
    else
        echo "Missing current_url or override_url"
    fi
else
    echo "Binary not found or not executable"
fi

rm -f "$temp_file"