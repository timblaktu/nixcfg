#!/usr/bin/env bash
# Bulk SSH Key Generation and Migration Script
# Generates or migrates SSH keys for all hosts and users to Bitwarden
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║   Bulk SSH Key Generation and Migration     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Configuration
HOSTS=("thinky-nixos" "mbp" "potato")
USERNAME="tim"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure rbw is unlocked
if ! rbw unlocked >/dev/null 2>&1; then
    echo -e "${YELLOW}Unlocking Bitwarden...${NC}"
    rbw unlock || rbw login
fi

# Sync vault
echo "Syncing Bitwarden vault..."
rbw sync

# Arrays to store keys
declare -A SSH_PUBLIC_KEYS
declare -A HOST_SSH_KEYS
FAILED_KEYS=()

echo ""
echo "Processing SSH keys for user $USERNAME on hosts: ${HOSTS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Function to store SSH key in Bitwarden
store_ssh_key() {
    local key_name=$1
    local key_content=$2
    
    # Check if key already exists
    if rbw get "$key_name" &>/dev/null; then
        echo -e "${YELLOW}   ⚠️  Key already exists: $key_name${NC}"
        echo "   Replace it? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rbw remove "$key_name"
        else
            return 1
        fi
    fi
    
    # Store in Bitwarden
    if echo "$key_content" | rbw add --folder "Infrastructure/SSH-Keys" "$key_name"; then
        return 0
    else
        return 1
    fi
}

# Process current host first (can access local SSH keys)
CURRENT_HOST=$(hostname)
echo ""
echo "🔑 Processing current host: $CURRENT_HOST"

if [ -f ~/.ssh/id_ed25519 ]; then
    echo -e "${BLUE}   Found existing SSH key${NC}"
    
    # Read keys
    PRIVATE_KEY=$(cat ~/.ssh/id_ed25519)
    PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
    
    # Prepare content for Bitwarden
    KEY_CONTENT=$(cat <<EOF
$PRIVATE_KEY

# Public key
$PUBLIC_KEY

# Generated: $(stat -c %y ~/.ssh/id_ed25519 2>/dev/null || echo "Unknown")
# Host: $CURRENT_HOST
# User: $USERNAME
EOF
)
    
    # Store in Bitwarden
    if store_ssh_key "ssh-user-${USERNAME}@${CURRENT_HOST}" "$KEY_CONTENT"; then
        echo -e "${GREEN}   ✅ Migrated SSH key to Bitwarden${NC}"
        SSH_PUBLIC_KEYS["${USERNAME}@${CURRENT_HOST}"]="$PUBLIC_KEY"
    else
        echo "   Keeping existing Bitwarden entry"
        # Try to get public key from Bitwarden
        EXISTING=$(rbw get "ssh-user-${USERNAME}@${CURRENT_HOST}" | grep "^ssh-" | head -1)
        if [ -n "$EXISTING" ]; then
            SSH_PUBLIC_KEYS["${USERNAME}@${CURRENT_HOST}"]="$EXISTING"
        fi
    fi
else
    echo -e "${YELLOW}   No existing SSH key found${NC}"
    echo "   Generate new key? (Y/n): "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "${USERNAME}@${CURRENT_HOST}" -N ""
        
        PRIVATE_KEY=$(cat ~/.ssh/id_ed25519)
        PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
        
        KEY_CONTENT=$(cat <<EOF
$PRIVATE_KEY

# Public key
$PUBLIC_KEY

# Generated: $(date -Iseconds)
# Host: $CURRENT_HOST
# User: $USERNAME
EOF
)
        
        if store_ssh_key "ssh-user-${USERNAME}@${CURRENT_HOST}" "$KEY_CONTENT"; then
            echo -e "${GREEN}   ✅ Generated and stored new SSH key${NC}"
            SSH_PUBLIC_KEYS["${USERNAME}@${CURRENT_HOST}"]="$PUBLIC_KEY"
        else
            FAILED_KEYS+=("${USERNAME}@${CURRENT_HOST}")
        fi
    fi
fi

# Generate keys for other hosts
echo ""
echo "🔐 Generating SSH keys for other hosts"
echo "   (These will be deployed when you set up each host)"

for HOST in "${HOSTS[@]}"; do
    # Skip current host
    if [ "$HOST" = "$CURRENT_HOST" ]; then
        continue
    fi
    
    echo ""
    echo "   Processing: ${USERNAME}@${HOST}"
    
    # Check if key exists in Bitwarden
    if rbw get "ssh-user-${USERNAME}@${HOST}" &>/dev/null; then
        echo -e "${YELLOW}   Key already exists in Bitwarden${NC}"
        # Get public key
        EXISTING=$(rbw get "ssh-user-${USERNAME}@${HOST}" | grep "^ssh-" | head -1)
        if [ -n "$EXISTING" ]; then
            SSH_PUBLIC_KEYS["${USERNAME}@${HOST}"]="$EXISTING"
        fi
        continue
    fi
    
    # Generate new key pair in memory
    TEMP_KEY=$(mktemp -d)
    ssh-keygen -t ed25519 -f "$TEMP_KEY/id_ed25519" -C "${USERNAME}@${HOST}" -N "" >/dev/null 2>&1
    
    PRIVATE_KEY=$(cat "$TEMP_KEY/id_ed25519")
    PUBLIC_KEY=$(cat "$TEMP_KEY/id_ed25519.pub")
    
    KEY_CONTENT=$(cat <<EOF
$PRIVATE_KEY

# Public key
$PUBLIC_KEY

# Generated: $(date -Iseconds)
# Host: $HOST
# User: $USERNAME
# Note: Pre-generated for future deployment
EOF
)
    
    if store_ssh_key "ssh-user-${USERNAME}@${HOST}" "$KEY_CONTENT"; then
        echo -e "${GREEN}   ✅ Generated and stored SSH key${NC}"
        SSH_PUBLIC_KEYS["${USERNAME}@${HOST}"]="$PUBLIC_KEY"
    else
        echo -e "${RED}   ❌ Failed to store key${NC}"
        FAILED_KEYS+=("${USERNAME}@${HOST}")
    fi
    
    # Clean up
    rm -rf "$TEMP_KEY"
done

# Also get host SSH keys if available
echo ""
echo "📋 Collecting host SSH public keys"
echo "   (Used for host verification)"

for HOST in "${HOSTS[@]}"; do
    if [ "$HOST" = "$CURRENT_HOST" ] && [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
        HOST_SSH_KEYS["$HOST"]=$(cat /etc/ssh/ssh_host_ed25519_key.pub)
        echo -e "${GREEN}   ✓ Found host key for $HOST${NC}"
    else
        echo "   ⚬ Host key for $HOST will be collected when host is set up"
    fi
done

# Generate SSH public keys registry module
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📄 Creating ssh-public-keys.nix module"

MODULE_FILE="ssh-public-keys.nix"
cat > "$MODULE_FILE" <<'EOF'
{ lib, ... }:
{
  options.sshPublicKeys = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Registry of all SSH public keys for centralized management";
  };
  
  config.sshPublicKeys = {
    users = {
      tim = {
EOF

# Add user SSH public keys
for KEY in "${!SSH_PUBLIC_KEYS[@]}"; do
    HOST=$(echo "$KEY" | cut -d'@' -f2)
    echo "        \"$HOST\" = \"${SSH_PUBLIC_KEYS[$KEY]}\";" >> "$MODULE_FILE"
done

cat >> "$MODULE_FILE" <<'EOF'
      };
    };
    
    hosts = {
      # Host SSH keys (for host verification)
      # These are the /etc/ssh/ssh_host_ed25519_key.pub keys
EOF

# Add host SSH public keys
for HOST in "${!HOST_SSH_KEYS[@]}"; do
    echo "      \"$HOST\" = \"${HOST_SSH_KEYS[$HOST]}\";" >> "$MODULE_FILE"
done

cat >> "$MODULE_FILE" <<'EOF'
      # Other hosts will be added as they are configured
    };
  };
}
EOF

echo -e "${GREEN}✅ Module created: $MODULE_FILE${NC}"

# Create deployment script for SSH keys
echo ""
echo "📄 Creating SSH key deployment script"

cat > deploy-ssh-keys.sh <<'DEPLOY_SCRIPT'
#!/usr/bin/env bash
# Deploy SSH Keys from Bitwarden to Host
set -euo pipefail

HOSTNAME="${1:-$(hostname)}"
USERNAME="${2:-$(whoami)}"
SSH_KEY_NAME="ssh-user-${USERNAME}@${HOSTNAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════╗"
echo "║     Deploying SSH Keys for $USERNAME@$HOSTNAME"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Ensure rbw is unlocked
if ! rbw unlocked >/dev/null 2>&1; then
    echo -e "${YELLOW}Unlocking Bitwarden...${NC}"
    rbw unlock || rbw login
fi

# Sync vault
rbw sync

# Backup existing keys if present
if [ -f ~/.ssh/id_ed25519 ]; then
    echo -e "${YELLOW}Backing up existing SSH keys...${NC}"
    cp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.backup.$(date +%s)
    cp ~/.ssh/id_ed25519.pub ~/.ssh/id_ed25519.pub.backup.$(date +%s)
fi

# Fetch SSH key from Bitwarden
echo "Fetching $SSH_KEY_NAME from Bitwarden..."
KEY_CONTENT=$(rbw get "$SSH_KEY_NAME" 2>/dev/null || echo "")

if [ -z "$KEY_CONTENT" ]; then
    echo -e "${RED}❌ SSH key not found in Bitwarden: $SSH_KEY_NAME${NC}"
    echo ""
    echo "Available SSH keys:"
    rbw list --folder "Infrastructure/SSH-Keys" | grep "ssh-user-" || echo "  None found"
    exit 1
fi

# Create SSH directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Extract and deploy private key
echo "$KEY_CONTENT" | sed -n '/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p' > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

# Extract and deploy public key
echo "$KEY_CONTENT" | grep '^ssh-' | head -1 > ~/.ssh/id_ed25519.pub
chmod 644 ~/.ssh/id_ed25519.pub

echo -e "${GREEN}✅ SSH keys deployed successfully${NC}"

# Add to SSH agent if running
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
    ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
    echo "Added key to SSH agent"
fi

# Display public key
echo ""
echo "Your SSH public key:"
cat ~/.ssh/id_ed25519.pub

echo ""
echo "Next steps:"
echo "1. Add this public key to authorized_keys on remote hosts"
echo "2. Test SSH connection: ssh localhost"
echo ""
DEPLOY_SCRIPT

chmod +x deploy-ssh-keys.sh
echo -e "${GREEN}✅ Created deployment script: deploy-ssh-keys.sh${NC}"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ${#FAILED_KEYS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Success! All SSH keys processed${NC}"
else
    echo -e "${YELLOW}⚠️  Completed with some issues${NC}"
    echo "Failed keys: ${FAILED_KEYS[*]}"
fi

echo ""
echo "📋 Files created:"
echo "   • $MODULE_FILE - NixOS module with public keys"
echo "   • deploy-ssh-keys.sh - Deployment script for hosts"
echo ""
echo "Next steps:"
echo "1. Review and move $MODULE_FILE to /home/tim/src/nixcfg/modules/nixos/"
echo "2. Import the module in your host configurations"
echo "3. Use deploy-ssh-keys.sh on each host to deploy keys"
echo "4. Configure authorized_keys using the sshPublicKeys registry"
echo ""