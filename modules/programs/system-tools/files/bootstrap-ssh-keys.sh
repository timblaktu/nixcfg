#!/usr/bin/env bash
#
# Bootstrap SSH Keys from Bitwarden
# 
# This script fetches SSH keypairs from Bitwarden using rbw CLI,
# deploys them to the appropriate locations, and generates new keys
# if they don't exist in Bitwarden.
#
# Usage: bootstrap-ssh-keys.sh [options]
# Options:
#   -u, --user <username>    Override default username
#   -h, --host <hostname>    Override default hostname  
#   -f, --force             Force regeneration of keys
#   -q, --quiet             Suppress non-error output
#   -v, --verbose           Enable verbose output
#   --help                  Show this help message

set -euo pipefail

# Configuration defaults
HOSTNAME="${HOSTNAME:-$(hostname)}"
USERNAME="${USER:-$(whoami)}"
SSH_DIR="${HOME}/.ssh"
SSH_KEY_TYPE="ed25519"
FORCE_REGENERATE=false
QUIET=false
VERBOSE=false
BW_FOLDER="Infrastructure/SSH-Keys"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $*"
    fi
}

log_info() {
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_warn() {
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $*"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[VERBOSE] $*"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                USERNAME="$2"
                shift 2
                ;;
            -h|--host)
                HOSTNAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_REGENERATE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    head -n 16 "$0" | tail -n 15 | sed 's/^# //'
}

# Check prerequisites
check_prerequisites() {
    log_verbose "Checking prerequisites..."
    
    # Check if rbw is installed
    if ! command -v rbw &> /dev/null; then
        log_error "rbw CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if rbw is unlocked
    if ! rbw unlocked &> /dev/null; then
        log_info "Bitwarden vault is locked. Attempting to unlock..."
        if ! rbw unlock; then
            log_error "Failed to unlock Bitwarden vault"
            exit 1
        fi
    fi
    
    # Ensure SSH directory exists with proper permissions
    if [[ ! -d "$SSH_DIR" ]]; then
        log_verbose "Creating SSH directory: $SSH_DIR"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
    
    log_verbose "Prerequisites check passed"
}

# Construct the SSH key name in Bitwarden
get_ssh_key_name() {
    echo "ssh-user-${USERNAME}@${HOSTNAME}"
}

# Check if SSH keys already exist locally
check_local_keys() {
    local private_key="$SSH_DIR/id_${SSH_KEY_TYPE}"
    local public_key="${private_key}.pub"
    
    if [[ -f "$private_key" && -f "$public_key" ]] && [[ "$FORCE_REGENERATE" == "false" ]]; then
        log_verbose "Local SSH keys already exist at $private_key"
        return 0
    fi
    return 1
}

# Fetch SSH keys from Bitwarden
fetch_from_bitwarden() {
    local ssh_key_name="$1"
    
    log_info "Fetching SSH key from Bitwarden: $ssh_key_name"
    
    # Try to get the key content from Bitwarden
    if KEY_CONTENT=$(rbw get --raw "$ssh_key_name" 2>/dev/null); then
        log_verbose "Successfully retrieved key from Bitwarden"
        echo "$KEY_CONTENT"
        return 0
    else
        log_verbose "SSH key not found in Bitwarden: $ssh_key_name"
        return 1
    fi
}

# Deploy SSH keys to filesystem
deploy_keys() {
    local key_content="$1"
    local private_key="$SSH_DIR/id_${SSH_KEY_TYPE}"
    local public_key="${private_key}.pub"
    
    log_info "Deploying SSH keys to $SSH_DIR"
    
    # Extract and save private key
    log_verbose "Extracting private key..."
    echo "$key_content" | sed -n '/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p' > "$private_key"
    
    if [[ ! -s "$private_key" ]]; then
        log_error "Failed to extract private key from Bitwarden entry"
        rm -f "$private_key"
        return 1
    fi
    
    chmod 600 "$private_key"
    log_verbose "Private key saved and permissions set to 600"
    
    # Extract and save public key
    log_verbose "Extracting public key..."
    echo "$key_content" | grep '^ssh-' | head -1 > "$public_key"
    
    if [[ ! -s "$public_key" ]]; then
        log_warn "Public key not found in Bitwarden entry, regenerating from private key..."
        ssh-keygen -y -f "$private_key" > "$public_key"
    fi
    
    chmod 644 "$public_key"
    log_verbose "Public key saved and permissions set to 644"
    
    log_success "SSH keys deployed successfully"
    return 0
}

# Generate new SSH keypair
generate_new_keys() {
    local private_key="$SSH_DIR/id_${SSH_KEY_TYPE}"
    local public_key="${private_key}.pub"
    
    log_info "Generating new SSH keypair..."
    
    # Backup existing keys if they exist
    if [[ -f "$private_key" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="${private_key}.backup.${timestamp}"
        log_warn "Backing up existing private key to: $backup"
        mv "$private_key" "$backup"
    fi
    
    if [[ -f "$public_key" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="${public_key}.backup.${timestamp}"
        log_warn "Backing up existing public key to: $backup"
        mv "$public_key" "$backup"
    fi
    
    # Generate new keypair
    ssh-keygen -t "$SSH_KEY_TYPE" -f "$private_key" -N "" -C "${USERNAME}@${HOSTNAME}"
    
    if [[ ! -f "$private_key" || ! -f "$public_key" ]]; then
        log_error "Failed to generate SSH keypair"
        return 1
    fi
    
    log_success "New SSH keypair generated successfully"
    return 0
}

# Store SSH keys in Bitwarden
store_in_bitwarden() {
    local ssh_key_name="$1"
    local private_key="$SSH_DIR/id_${SSH_KEY_TYPE}"
    local public_key="${private_key}.pub"
    
    log_info "Storing SSH keys in Bitwarden as: $ssh_key_name"
    
    # Prepare the content with both private and public keys
    local key_content
    key_content=$(cat <<EOF
$(cat "$private_key")

# Public key (for reference)
$(cat "$public_key")

# Generated on $(date -Iseconds)
# Host: ${HOSTNAME}
# User: ${USERNAME}
EOF
)
    
    # Create folder if it doesn't exist (rbw will handle this)
    log_verbose "Using Bitwarden folder: $BW_FOLDER"
    
    # Store in Bitwarden
    # First try to create the entry
    if echo "$key_content" | rbw add --uri "ssh://${HOSTNAME}" --folder "$BW_FOLDER" "$ssh_key_name" 2>/dev/null; then
        log_success "SSH keys stored in Bitwarden successfully"
        return 0
    else
        # If entry exists, update it
        log_verbose "Entry might exist, attempting to update..."
        if echo "$key_content" | rbw edit "$ssh_key_name" 2>/dev/null; then
            log_success "SSH keys updated in Bitwarden successfully"
            return 0
        else
            log_error "Failed to store SSH keys in Bitwarden"
            return 1
        fi
    fi
}

# Add key to SSH agent if running
add_to_agent() {
    local private_key="$SSH_DIR/id_${SSH_KEY_TYPE}"
    
    # Check if SSH agent is running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_verbose "SSH agent not running, skipping agent addition"
        return 0
    fi
    
    log_info "Adding key to SSH agent..."
    
    if ssh-add "$private_key" 2>/dev/null; then
        log_success "Key added to SSH agent"
    else
        log_warn "Failed to add key to SSH agent (this is not critical)"
    fi
}

# Main function
main() {
    parse_args "$@"
    
    log_info "Starting SSH key bootstrap for ${USERNAME}@${HOSTNAME}"
    
    check_prerequisites
    
    local ssh_key_name
    ssh_key_name=$(get_ssh_key_name)
    log_verbose "Using SSH key name: $ssh_key_name"
    
    # Check if we should skip due to existing local keys
    if check_local_keys && [[ "$FORCE_REGENERATE" == "false" ]]; then
        log_success "Local SSH keys already exist, skipping bootstrap"
        add_to_agent
        exit 0
    fi
    
    # Try to fetch from Bitwarden first
    if KEY_CONTENT=$(fetch_from_bitwarden "$ssh_key_name"); then
        # Deploy the fetched keys
        if deploy_keys "$KEY_CONTENT"; then
            add_to_agent
            log_success "SSH key bootstrap completed successfully"
            exit 0
        else
            log_warn "Failed to deploy keys from Bitwarden, will generate new ones"
        fi
    else
        log_info "SSH key not found in Bitwarden, will generate new keypair"
    fi
    
    # Generate new keys if we couldn't fetch or deploy from Bitwarden
    if generate_new_keys; then
        # Store the new keys in Bitwarden
        if store_in_bitwarden "$ssh_key_name"; then
            log_success "New SSH keys generated and stored in Bitwarden"
        else
            log_warn "Generated new SSH keys but failed to store in Bitwarden"
            log_warn "Keys are available locally but won't be backed up to Bitwarden"
        fi
        add_to_agent
        log_success "SSH key bootstrap completed successfully"
    else
        log_error "Failed to generate SSH keys"
        exit 1
    fi
}

# Run main function
main "$@"