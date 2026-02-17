#!/usr/bin/env bash
set -euo pipefail

export KEYS_DIR="${KEYS_DIR:-$HOME/.config/sops/age}"
export BW_ENTRY_NAME="${BW_ENTRY_NAME:-NixOS Bootstrap Key}"
export BW_EMAIL="${BW_EMAIL:-}"
export BW_PINENTRY="${BW_PINENTRY:-pinentry-curses}"
export BW_CLIENTID="${BW_CLIENTID:-}"
export BW_CLIENT_SECRET="${BW_CLIENT_SECRET:-}"
export BW_IDENTITY_URL="${BW_IDENTITY_URL:-}"
export BW_API_URL="${BW_API_URL:-}"
export RBW_LOCK_TIMEOUT="${RBW_LOCK_TIMEOUT:-86400}"  # Default to 24 hours (86400 seconds)
export NIX_CONFIG="experimental-features = nix-command flakes"

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: Nix package manager not found. Please install Nix first."
  echo "Visit https://nixos.org/download.html for installation instructions."
  exit 1
fi

echo "Fetching bootstrap key from Bitwarden using RBW..."
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

set +e
read -d "" -r RBW_SCRIPT << 'EORBW'
#!/usr/bin/env bash
set -euo pipefail

# Initialize config if needed
if [ ! -f "$HOME/.config/rbw/config.json" ]; then
  echo "Setting up RBW configuration..."
  
  # Prepare arguments for rbw config setup
  SETUP_ARGS=()
  [ -n "$BW_EMAIL" ] && SETUP_ARGS+=(--email "$BW_EMAIL")
  [ -n "$BW_PINENTRY" ] && SETUP_ARGS+=(--pinentry "$BW_PINENTRY")
  
  if [ -n "${BW_CLIENTID:-}" ]; then
    SETUP_ARGS+=(
      --identity-url "${BW_IDENTITY_URL:-https://identity.bitwarden.com}"
      --api-url "${BW_API_URL:-https://api.bitwarden.com}"
      --client-id "$BW_CLIENTID"
    )
    [ -n "${BW_CLIENT_SECRET:-}" ] && SETUP_ARGS+=(--client-secret "$BW_CLIENT_SECRET")
  fi

  rbw config setup "${SETUP_ARGS[@]}"
  
  # Set a longer lock timeout to prevent frequent password prompts
  rbw config set lock_timeout "$RBW_LOCK_TIMEOUT"
else
  # Update key configs if environment variables are provided
  [ -n "$BW_EMAIL" ] && rbw config set email "$BW_EMAIL"
  [ -n "$BW_PINENTRY" ] && rbw config set pinentry "$BW_PINENTRY"
  
  # Check and update lock_timeout if needed
  CURRENT_TIMEOUT=$(rbw config get lock_timeout 2>/dev/null || echo "3600")
  if [ "$CURRENT_TIMEOUT" != "$RBW_LOCK_TIMEOUT" ]; then
    echo "Updating lock timeout to $RBW_LOCK_TIMEOUT seconds"
    rbw config set lock_timeout "$RBW_LOCK_TIMEOUT"
  fi
  
  if [ -n "${BW_CLIENTID:-}" ]; then
    rbw config set identity_url "${BW_IDENTITY_URL:-https://identity.bitwarden.com}"
    rbw config set api_url "${BW_API_URL:-https://api.bitwarden.com}"
    rbw config set client_id "$BW_CLIENTID"
    [ -n "${BW_CLIENT_SECRET:-}" ] && rbw config set client_secret "$BW_CLIENT_SECRET"
  fi
fi

# Restart the agent to apply new settings and clear any locked state
echo "Ensuring rbw-agent is running with updated settings..."
rbw stop-agent >/dev/null 2>&1 || true
sleep 1

# Check if the sync_interval is set - if not, set it to a high value
# This keeps the agent running persistently
SYNC_INTERVAL=$(rbw config get sync_interval 2>/dev/null || echo "3600")
if [ "$SYNC_INTERVAL" != "86400" ]; then
  echo "Setting sync interval to 86400 seconds to keep agent persistent"
  rbw config set sync_interval 86400
fi

echo "Logging into Bitwarden and syncing vault..."
# Check if already unlocked to avoid password prompt
if ! rbw unlocked >/dev/null 2>&1; then
  rbw unlock || rbw login
fi

rbw sync

echo "Retrieving secret from Bitwarden entry: $BW_ENTRY_NAME"
SECRET_CONTENT=$(rbw get -f notes "$BW_ENTRY_NAME" 2>/dev/null || echo "")

if [ -z "$SECRET_CONTENT" ]; then
  echo "Error: Secret '$BW_ENTRY_NAME' not found in your Bitwarden vault."
  echo ""
  echo "Please create a secure note in Bitwarden with the following:"
  echo "1. Name it exactly: $BW_ENTRY_NAME"
  echo "2. Generate an Age key pair:"
  echo "   $ nix shell nixpkgs#age --command age-keygen -o age-key.txt"
  echo "3. Copy the ENTIRE contents of age-key.txt into the note field"
  echo "4. Run this script again after creating the secret"
  exit 1
fi

if ! echo "$SECRET_CONTENT" | grep -q "AGE-SECRET-KEY-"; then
  echo "Error: The retrieved content does not appear to be a valid Age key."
  echo "Please check that your Bitwarden entry contains a proper Age key."
  exit 1
fi

echo "$SECRET_CONTENT" > "$KEYS_DIR/keys.txt"
EORBW
set -e

echo "calling nix shell.."
nix shell nixpkgs#rbw --command bash -c "$RBW_SCRIPT" | sed 's/^/    /'
echo "nix shell returned $?"

chmod 600 "$KEYS_DIR/keys.txt"
echo "Bootstrap complete. SOPS key is now available at $KEYS_DIR/keys.txt"

nix shell nixpkgs#age --command bash -c "
if command -v age-keygen >/dev/null 2>&1; then
  echo 'Public key for .sops.yaml:'
  age-keygen -y '$KEYS_DIR/keys.txt'
fi
"

echo "You can now run: nixos-rebuild switch --flake .#mbp"
