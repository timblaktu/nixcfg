#!/usr/bin/env bash
# Deploy Age Key from Bitwarden to Host
# Retrieves pre-generated age key from Bitwarden and installs it
set -euo pipefail

HOSTNAME="${1:-$(hostname)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════╗"
echo "║     Deploying Age Key for $HOSTNAME"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Check if running with appropriate permissions
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Running as root. Will use sudo -u to call rbw as user.${NC}"
    if [ -z "${SUDO_USER:-}" ]; then
        echo -e "${RED}❌ Cannot determine original user. Please run without sudo.${NC}"
        exit 1
    fi
    RBW_CMD="sudo -u $SUDO_USER rbw"
else
    RBW_CMD="rbw"
fi

# Ensure rbw is unlocked
if ! $RBW_CMD unlocked >/dev/null 2>&1; then
    echo -e "${YELLOW}Unlocking Bitwarden...${NC}"
    $RBW_CMD unlock || $RBW_CMD login
fi

# Sync vault
echo "Syncing Bitwarden vault..."
$RBW_CMD sync

# Check if age key already exists on system
if [ -f /etc/sops/age.key ]; then
    echo -e "${YELLOW}⚠️  Age key already exists at /etc/sops/age.key${NC}"
    echo "Current public key:"
    sudo age-keygen -y /etc/sops/age.key 2>/dev/null || echo "  (Unable to read current key)"
    echo ""
    echo "Replace with key from Bitwarden? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Keeping existing key."
        exit 0
    fi
fi

# Fetch age key from Bitwarden
echo "Fetching age-key-host-$HOSTNAME from Bitwarden..."
KEY_CONTENT=$($RBW_CMD get "age-key-host-$HOSTNAME" 2>/dev/null || echo "")

if [ -z "$KEY_CONTENT" ]; then
    echo -e "${RED}❌ No age key found in Bitwarden for host: $HOSTNAME${NC}"
    echo ""
    echo "Available age keys in Bitwarden:"
    $RBW_CMD list --folder "Infrastructure/Age-Keys" 2>/dev/null | grep "age-key-host-" || echo "  None found"
    echo ""
    echo "Run ./generate-all-age-keys.sh first to create keys"
    exit 1
fi

# Extract just the key part (AGE-SECRET-KEY line)
KEY_ONLY=$(echo "$KEY_CONTENT" | grep "^AGE-SECRET-KEY-" | head -1)

if [ -z "$KEY_ONLY" ]; then
    echo -e "${RED}❌ Invalid key format in Bitwarden${NC}"
    echo "Key content doesn't contain AGE-SECRET-KEY line"
    exit 1
fi

# Extract public key from metadata if available
PUBLIC_KEY_FROM_META=$(echo "$KEY_CONTENT" | grep "^# Public key:" | cut -d' ' -f4 || echo "")

# Deploy the key
echo "Deploying age key to /etc/sops/age.key..."
sudo mkdir -p /etc/sops
echo "$KEY_ONLY" | sudo tee /etc/sops/age.key > /dev/null
sudo chmod 600 /etc/sops/age.key
sudo chown root:root /etc/sops/age.key

echo -e "${GREEN}✅ Age key deployed successfully${NC}"

# Verify by showing public key
if command -v age-keygen &> /dev/null; then
    echo ""
    echo "Verification - Public key from deployed key:"
    DEPLOYED_PUBLIC=$(sudo age-keygen -y /etc/sops/age.key)
    echo "  $DEPLOYED_PUBLIC"
    
    if [ -n "$PUBLIC_KEY_FROM_META" ]; then
        echo ""
        echo "Expected public key from Bitwarden metadata:"
        echo "  $PUBLIC_KEY_FROM_META"
        
        if [ "$DEPLOYED_PUBLIC" = "$PUBLIC_KEY_FROM_META" ]; then
            echo -e "${GREEN}✅ Public keys match - deployment verified!${NC}"
        else
            echo -e "${YELLOW}⚠️  Public keys don't match - please verify${NC}"
        fi
    fi
fi

echo ""
echo "Next steps:"
echo "1. Update .sops.yaml with this host's public key (if not already done)"
echo "2. Test SOPS encryption/decryption with: sops secrets/common/test.yaml"
echo "3. Deploy NixOS configuration with SOPS-NiX enabled"
echo ""