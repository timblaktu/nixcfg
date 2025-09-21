#!/usr/bin/env bash
# Bulk Age Key Generation Script
# Generates age keys for all hosts and stores them in Bitwarden
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║   Bulk Age Key Generation for All Hosts     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Define all active hosts
HOSTS=("mbp" "potato")  # thinky-nixos already has keys, tblack-t14-nixos is archived

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure age is installed
if ! command -v age-keygen &> /dev/null; then
    echo -e "${YELLOW}Installing age...${NC}"
    nix-env -iA nixpkgs.age
fi

# Ensure rbw is unlocked
if ! rbw unlocked >/dev/null 2>&1; then
    echo -e "${YELLOW}Unlocking Bitwarden...${NC}"
    rbw unlock || rbw login
fi

# Sync vault
echo "Syncing Bitwarden vault..."
rbw sync

# Array to store public keys for .sops.yaml
declare -A PUBLIC_KEYS

# Track success/failure
FAILED_HOSTS=()

echo ""
echo "Generating age keys for hosts: ${HOSTS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Generate keys for each host
for HOST in "${HOSTS[@]}"; do
    echo ""
    echo "🔑 Processing host: $HOST"
    
    # Check if key already exists in Bitwarden
    if rbw get "age-key-host-$HOST" &>/dev/null; then
        echo -e "${YELLOW}   ⚠️  Key already exists in Bitwarden for $HOST${NC}"
        echo "   Would you like to replace it? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "   Skipping $HOST..."
            # Fetch existing public key if possible
            EXISTING_KEY=$(rbw get "age-key-host-$HOST" | grep "^# Public key:" | cut -d' ' -f4 || echo "")
            if [ -n "$EXISTING_KEY" ]; then
                PUBLIC_KEYS[$HOST]=$EXISTING_KEY
            fi
            continue
        fi
        # Remove existing key
        rbw remove "age-key-host-$HOST"
    fi
    
    # Generate key to temp file
    TEMP_KEY=$(mktemp)
    if ! age-keygen -o "$TEMP_KEY" 2>/dev/null; then
        echo -e "${RED}   ❌ Failed to generate key for $HOST${NC}"
        FAILED_HOSTS+=("$HOST")
        rm -f "$TEMP_KEY"
        continue
    fi
    
    # Get public key
    PUBLIC_KEY=$(age-keygen -y "$TEMP_KEY")
    PUBLIC_KEYS[$HOST]=$PUBLIC_KEY
    
    # Prepare content for Bitwarden (key + metadata)
    {
        cat "$TEMP_KEY"
        echo ""
        echo "# Public key: $PUBLIC_KEY"
        echo "# Generated: $(date -Iseconds)"
        echo "# Host: $HOST"
        echo "# Generator: bulk age key initialization"
    } > "${TEMP_KEY}.full"
    
    # Store in Bitwarden
    if cat "${TEMP_KEY}.full" | rbw add --folder "Infrastructure/Age-Keys" "age-key-host-$HOST"; then
        echo -e "${GREEN}   ✅ Stored age-key-host-$HOST in Bitwarden${NC}"
        echo "   📋 Public key: $PUBLIC_KEY"
    else
        echo -e "${RED}   ❌ Failed to store key in Bitwarden for $HOST${NC}"
        FAILED_HOSTS+=("$HOST")
    fi
    
    # Clean up temp files
    rm -f "$TEMP_KEY" "${TEMP_KEY}.full"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Generate .sops.yaml snippet
echo ""
echo "📄 Update .sops.yaml with these public keys:"
echo "────────────────────────────────────────"
cat << EOF
keys:
  # Users
  - &user_tim age1s3w0vh40qtjzx677xdda7lv5sqnhrxg9ae306zrkx4deurcvx90sajtlsk
  
  # Hosts
  - &host_thinky age1rz0k6055dsat660rs3y8jdypmjxdjwaya2w4v0x6q7646m6n8atszz0vzx
EOF

for HOST in "${HOSTS[@]}"; do
    if [[ -n "${PUBLIC_KEYS[$HOST]:-}" ]]; then
        echo "  - &host_${HOST} ${PUBLIC_KEYS[$HOST]}"
    fi
done

echo ""
echo "creation_rules:"
echo "  - path_regex: secrets/common/[^/]+\\.(yaml|json|env)\$"
echo "    key_groups:"
echo "    - age:"
echo "      - *user_tim"
echo "      - *host_thinky"
for HOST in "${HOSTS[@]}"; do
    if [[ -n "${PUBLIC_KEYS[$HOST]:-}" ]]; then
        echo "      - *host_${HOST}"
    fi
done

# Save public keys to a file for reference
OUTPUT_FILE="generated-age-public-keys.txt"
{
    echo "# Age Public Keys Generated $(date -Iseconds)"
    echo "# This file is for reference only - actual keys are in Bitwarden"
    echo ""
    echo "thinky-nixos: age1rz0k6055dsat660rs3y8jdypmjxdjwaya2w4v0x6q7646m6n8atszz0vzx"
    for HOST in "${HOSTS[@]}"; do
        if [[ -n "${PUBLIC_KEYS[$HOST]:-}" ]]; then
            echo "$HOST: ${PUBLIC_KEYS[$HOST]}"
        fi
    done
} > "$OUTPUT_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Summary
if [ ${#FAILED_HOSTS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Success! All age keys generated and stored in Bitwarden${NC}"
else
    echo -e "${YELLOW}⚠️  Completed with some issues${NC}"
    echo "Failed hosts: ${FAILED_HOSTS[*]}"
fi

echo ""
echo "📋 Public keys saved to: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Copy the .sops.yaml content above and update /home/tim/src/nixcfg/.sops.yaml"
echo "2. Commit the .sops.yaml changes"
echo "3. When setting up each host, run: ./deploy-age-key.sh"
echo ""