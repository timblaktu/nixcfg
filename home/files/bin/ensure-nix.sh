#!/usr/bin/env bash
set -euo pipefail

# Check if Nix is already available
if command -v nix &> /dev/null; then
    echo '{"hookSpecificOutput": {"additionalContext": "Nix already available. Use: nix develop"}}'
    exit 0
fi

# Detect if this is a cloud session (fresh environment)
IS_CLOUD=false
if [ ! -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
    IS_CLOUD=true
fi

# Install Nix in cloud sessions only
if [ "$IS_CLOUD" = true ]; then
    echo "Installing Nix (one-time setup, ~2-3 minutes)..."
    
    # Single-user install (no sudo required)
    sh <(curl -L https://nixos.org/nix/install) --no-daemon --yes
    
    # Source nix for current session
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    # Enable flakes and configure
    mkdir -p ~/.config/nix
    cat > ~/.config/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
# Binary cache configuration will be added here in next session
EOF
    
    echo '{"hookSpecificOutput": {"additionalContext": "Nix installed successfully. Environment ready. Use: nix develop"}}'
else
    echo '{"hookSpecificOutput": {"additionalContext": "Nix environment ready. Use: nix develop"}}'
fi
