#!/usr/bin/env bash
# Quick fix for systemd user session after WSL restart
# Issue: /run/user/1000 gets created with root:root ownership
# Root cause: WSL doesn't honor user ownership on runtime dir creation

set -e

echo "Fixing /run/user/1000 ownership..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "Error: Don't run this script with sudo. It will call sudo internally."
    exit 1
fi

# Check current ownership
current_owner=$(stat -c "%U:%G" /run/user/1000 2>/dev/null || echo "missing")
if [[ "$current_owner" == "tim:users" ]]; then
    echo "✓ Ownership already correct: $current_owner"
else
    echo "Current ownership: $current_owner (should be tim:users)"
    echo "Fixing ownership..."
    sudo chown -R tim:users /run/user/1000
    sudo chmod 0700 /run/user/1000
    echo "✓ Ownership fixed"
fi

# Check systemd user session status
if systemctl --user status &>/dev/null; then
    echo "✓ systemd --user already running"
else
    echo "Starting systemd user session..."
    sudo systemctl start user@1000.service
    sleep 2
    if systemctl --user status &>/dev/null; then
        echo "✓ systemd --user started successfully"
    else
        echo "✗ Failed to start systemd --user"
        exit 1
    fi
fi

echo ""
echo "All done! marker-pdf-env is ready to use."
