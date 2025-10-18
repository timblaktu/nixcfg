#!/usr/bin/env bash
# Master Secrets Initialization Script
# Orchestrates the complete secrets setup process with comprehensive validation
set -euo pipefail

# Enable debug mode if DEBUG env var is set
[[ "${DEBUG:-}" == "1" ]] && set -x

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NIXCFG_ROOT="$(dirname "$SCRIPT_DIR")"
LOGFILE="${SCRIPT_DIR}/initialization.log"
FAILED_PHASES=()
COMPLETED_PHASES=()

# Trap errors and cleanup
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_num=$2
    echo -e "${RED}❌ Error occurred at line $line_num with exit code $exit_code${NC}" | tee -a "$LOGFILE"
    echo "Check $LOGFILE for details"
    exit $exit_code
}

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

log_and_print() {
    echo -e "$@"
    # Strip color codes for log file
    echo "$@" | sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r line; do
        log "$line"
    done
}

# Header
clear
echo -e "${CYAN}" | tee "$LOGFILE"
echo "╔══════════════════════════════════════════════════════╗" | tee -a "$LOGFILE"
echo "║       Complete Secrets Infrastructure Setup         ║" | tee -a "$LOGFILE"
echo "║              Powered by Bitwarden + SOPS            ║" | tee -a "$LOGFILE"
echo "╚══════════════════════════════════════════════════════╝" | tee -a "$LOGFILE"
echo -e "${NC}" | tee -a "$LOGFILE"
log "Starting initialization script from $SCRIPT_DIR"

# Function to check prerequisites
check_prerequisites() {
    log_and_print "\n🔍 ${BOLD}Checking prerequisites...${NC}"
    
    local missing_tools=()
    local optional_missing=()
    
    # Required tools
    local required_tools=(age age-keygen sops rbw)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_and_print "  ${GREEN}✓${NC} $tool found at $(command -v "$tool")"
        fi
    done
    
    # Optional but recommended tools
    local optional_tools=(jq git)
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            optional_missing+=("$tool")
            log_and_print "  ${YELLOW}⚬${NC} $tool not found (optional)"
        else
            log_and_print "  ${GREEN}✓${NC} $tool found"
        fi
    done
    
    # Handle missing required tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_and_print "\n${YELLOW}⚠️  Missing required tools: ${missing_tools[*]}${NC}"
        echo -n "Install missing tools? (Y/n): "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            log "Installing missing tools: ${missing_tools[*]}"
            if command -v nix-env &> /dev/null; then
                nix-env -iA nixpkgs.age nixpkgs.sops nixpkgs.rbw nixpkgs.jq nixpkgs.git
            else
                log_and_print "${RED}Nix not found. Please install required tools manually:${NC}"
                log_and_print "  ${missing_tools[*]}"
                return 1
            fi
        else
            log_and_print "${RED}Cannot proceed without required tools${NC}"
            return 1
        fi
    fi
    
    # Check script files
    log_and_print "\n📁 ${BOLD}Checking script files...${NC}"
    local required_scripts=(
        "generate-all-age-keys.sh"
        "generate-all-ssh-keys.sh"
        "deploy-age-key.sh"
    )
    
    local missing_scripts=()
    for script in "${required_scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [ -x "$SCRIPT_DIR/$script" ]; then
                log_and_print "  ${GREEN}✓${NC} $script (executable)"
            else
                log_and_print "  ${YELLOW}⚬${NC} $script (not executable, fixing...)"
                chmod +x "$SCRIPT_DIR/$script"
            fi
        else
            missing_scripts+=("$script")
            log_and_print "  ${RED}✗${NC} $script missing"
        fi
    done
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        log_and_print "${RED}Missing required scripts. Please ensure all scripts are present.${NC}"
        return 1
    fi
    
    return 0
}

# Function to check Bitwarden status with better error handling
check_bitwarden() {
    log_and_print "\n🔓 ${BOLD}Checking Bitwarden status...${NC}"
    
    # Check if rbw is configured
    if ! rbw config show &>/dev/null; then
        log_and_print "${YELLOW}Bitwarden CLI (rbw) is not configured${NC}"
        log_and_print "Running rbw config setup..."
        
        echo -n "Enter your Bitwarden email: "
        read -r email
        rbw config set email "$email"
        
        log "Configured rbw with email: $email"
    fi
    
    # Check if unlocked
    if ! rbw unlocked &>/dev/null; then
        log_and_print "${YELLOW}Bitwarden is locked. Attempting to unlock...${NC}"
        
        # Try unlock first, then login if that fails
        if ! rbw unlock 2>/dev/null; then
            log "Unlock failed, attempting login"
            if ! rbw login; then
                log_and_print "${RED}Failed to login to Bitwarden${NC}"
                return 1
            fi
        fi
    fi
    
    # Sync vault
    log "Syncing Bitwarden vault"
    if rbw sync; then
        log_and_print "${GREEN}✅ Bitwarden is ready and synced${NC}"
        
        # Show vault statistics
        local total_items=$(rbw list 2>/dev/null | wc -l || echo "0")
        log_and_print "  Total items in vault: $total_items"
    else
        log_and_print "${RED}Failed to sync Bitwarden vault${NC}"
        return 1
    fi
    
    return 0
}

# Preview function to show what will be done
preview_actions() {
    local phase=$1
    
    echo -e "\n${BOLD}This phase will:${NC}"
    
    case $phase in
        "age")
            echo "  • Generate age encryption keys for hosts: mbp, potato"
            echo "  • Store keys securely in Bitwarden folder: Infrastructure/Age-Keys"
            echo "  • Output public keys for .sops.yaml configuration"
            echo "  • Save public keys to reference file"
            ;;
        "ssh")
            echo "  • Check for existing SSH keys on current host"
            echo "  • Migrate existing keys to Bitwarden if found"
            echo "  • Generate SSH keys for all configured hosts"
            echo "  • Create ssh-public-keys.nix module"
            echo "  • Create deployment script for each host"
            ;;
        "secrets")
            echo "  • Create/update .sops.yaml if needed"
            echo "  • Generate secret template files:"
            echo "    - services.yaml.template (API keys, tokens)"
            echo "    - wifi.yaml.template (network credentials)"
            echo "    - environment.yaml.template (env variables)"
            echo "  • Create directory structure for secrets"
            ;;
        "full")
            echo "  • Run all phases in sequence with validation"
            echo "  • Age keys generation"
            echo "  • SSH keys generation/migration"
            echo "  • Secrets templates creation"
            echo "  • Full status check at the end"
            ;;
    esac
    
    echo -n -e "\n${BOLD}Proceed? (Y/n):${NC} "
    read -r response
    [[ "$response" =~ ^[Nn]$ ]] && return 1
    return 0
}

# Function to run age keys generation with validation
run_age_keys() {
    log_and_print "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    log_and_print "${BLUE}           Phase 1: Age Keys Generation                 ${NC}"
    log_and_print "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    if ! preview_actions "age"; then
        log "User skipped age keys generation"
        return 1
    fi
    
    if [ -f "$SCRIPT_DIR/generate-all-age-keys.sh" ]; then
        log "Running generate-all-age-keys.sh"
        if bash "$SCRIPT_DIR/generate-all-age-keys.sh"; then
            COMPLETED_PHASES+=("age_keys")
            
            # Validate output
            if [ -f "$SCRIPT_DIR/generated-age-public-keys.txt" ]; then
                log_and_print "\n${GREEN}✅ Age keys generation completed successfully${NC}"
                log_and_print "  Public keys saved to: generated-age-public-keys.txt"
                
                # Show reminder about .sops.yaml
                log_and_print "\n${YELLOW}📝 Remember to update .sops.yaml with the generated public keys${NC}"
            else
                log_and_print "${YELLOW}⚠️  Public keys file not created - check for errors${NC}"
            fi
        else
            FAILED_PHASES+=("age_keys")
            log_and_print "${RED}❌ Age keys generation failed${NC}"
            return 1
        fi
    else
        log_and_print "${RED}❌ generate-all-age-keys.sh not found${NC}"
        return 1
    fi
}

# Function to run SSH keys generation with validation
run_ssh_keys() {
    log_and_print "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    log_and_print "${BLUE}         Phase 2: SSH Keys Generation/Migration         ${NC}"
    log_and_print "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    if ! preview_actions "ssh"; then
        log "User skipped SSH keys generation"
        return 1
    fi
    
    if [ -f "$SCRIPT_DIR/generate-all-ssh-keys.sh" ]; then
        log "Running generate-all-ssh-keys.sh"
        if bash "$SCRIPT_DIR/generate-all-ssh-keys.sh"; then
            COMPLETED_PHASES+=("ssh_keys")
            
            # Validate output
            if [ -f "$SCRIPT_DIR/ssh-public-keys.nix" ]; then
                log_and_print "\n${GREEN}✅ SSH keys generation completed successfully${NC}"
                log_and_print "  Module created: ssh-public-keys.nix"
                log_and_print "  ${YELLOW}Remember to move to: /home/tim/src/nixcfg/modules/nixos/${NC}"
            fi
            
            if [ -f "$SCRIPT_DIR/deploy-ssh-keys.sh" ]; then
                chmod +x "$SCRIPT_DIR/deploy-ssh-keys.sh"
                log_and_print "  Deployment script created: deploy-ssh-keys.sh"
            fi
        else
            FAILED_PHASES+=("ssh_keys")
            log_and_print "${RED}❌ SSH keys generation failed${NC}"
            return 1
        fi
    else
        log_and_print "${RED}❌ generate-all-ssh-keys.sh not found${NC}"
        return 1
    fi
}

# Function to create secrets templates with validation
run_secrets_templates() {
    log_and_print "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    log_and_print "${BLUE}         Phase 3: Production Secrets Templates          ${NC}"
    log_and_print "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    if ! preview_actions "secrets"; then
        log "User skipped secrets templates creation"
        return 1
    fi
    
    # Check if .sops.yaml exists
    if [ ! -f "$NIXCFG_ROOT/.sops.yaml" ]; then
        log_and_print "${YELLOW}⚠️  .sops.yaml not found. Creating from template...${NC}"
        
        # Get user's public key
        USER_AGE_KEY=""
        if [ -f ~/.config/sops/age/keys.txt ]; then
            USER_AGE_KEY=$(age-keygen -y ~/.config/sops/age/keys.txt 2>/dev/null || echo "")
            log "Found user age key: ${USER_AGE_KEY:0:20}..."
        fi
        
        if [ -z "$USER_AGE_KEY" ]; then
            log_and_print "${RED}❌ No user age key found at ~/.config/sops/age/keys.txt${NC}"
            log_and_print "Please run age keys generation first or create manually:"
            log_and_print "  mkdir -p ~/.config/sops/age"
            log_and_print "  age-keygen -o ~/.config/sops/age/keys.txt"
            return 1
        fi
        
        # Get host public keys if available
        HOST_KEYS=""
        if [ -f "$SCRIPT_DIR/generated-age-public-keys.txt" ]; then
            log "Reading generated age public keys"
            while IFS=': ' read -r host key; do
                [[ "$host" =~ ^#.*$ ]] && continue
                [[ -z "$host" ]] && continue
                HOST_KEYS="${HOST_KEYS}  - &host_${host} ${key}\n"
            done < "$SCRIPT_DIR/generated-age-public-keys.txt"
        fi
        
        cat > "$NIXCFG_ROOT/.sops.yaml" <<EOF
keys:
  # Users
  - &user_tim $USER_AGE_KEY
  
  # Hosts
$(echo -e "$HOST_KEYS" || echo "  # Run generate-all-age-keys.sh to populate host keys")

creation_rules:
  - path_regex: secrets/common/[^/]+\.(yaml|json|env)$
    key_groups:
    - age:
      - *user_tim
      # Add host references here after generating keys
  
  - path_regex: secrets/hosts/[^/]+/[^/]+\.(yaml|json|env)$
    key_groups:
    - age:
      - *user_tim
      # Host-specific keys added by path
EOF
        log_and_print "${GREEN}✅ Created .sops.yaml${NC}"
        [ -z "$HOST_KEYS" ] && log_and_print "${YELLOW}   Remember to update with host public keys after generation!${NC}"
    else
        log_and_print "${GREEN}✓ .sops.yaml already exists${NC}"
    fi
    
    # Create directory structure
    mkdir -p "$SCRIPT_DIR/common"
    mkdir -p "$SCRIPT_DIR/hosts"
    log "Created directory structure"
    
    # Track created templates
    local templates_created=0
    
    # Create services template
    if [ ! -f "$SCRIPT_DIR/common/services.yaml" ] && [ ! -f "$SCRIPT_DIR/common/services.yaml.template" ]; then
        log "Creating services.yaml.template"
        cat > "$SCRIPT_DIR/common/services.yaml.template" <<'EOF'
# Production Services Secrets Template
# Copy this to services.yaml and edit with: sops services.yaml

# GitHub Integration
github_token: "Placeholder_ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# API Keys
openai_api_key: "Placeholder_sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
anthropic_api_key: "Placeholder_sk-ant-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Database Passwords
postgres_password: "GENERATE_SECURE_PASSWORD"
redis_password: "GENERATE_SECURE_PASSWORD"

# Application Secrets
nextcloud_admin_password: "GENERATE_SECURE_PASSWORD"
grafana_admin_password: "GENERATE_SECURE_PASSWORD"

# Service Tokens
discord_bot_token: "Placeholder_DISCORD_BOT_TOKEN_HERE"
slack_webhook_url: "Placeholder_SLACK_WEBHOOK_URL_FORMAT_hooks.slack.com/services/TEAM/CHANNEL/TOKEN"
EOF
        log_and_print "  ${GREEN}✓${NC} Created services.yaml.template"
        ((templates_created++))
    fi
    
    # Create WiFi template
    if [ ! -f "$SCRIPT_DIR/common/wifi.yaml" ] && [ ! -f "$SCRIPT_DIR/common/wifi.yaml.template" ]; then
        log "Creating wifi.yaml.template"
        cat > "$SCRIPT_DIR/common/wifi.yaml.template" <<'EOF'
# WiFi Networks Configuration Template
# Copy this to wifi.yaml and edit with: sops wifi.yaml

wirelessNetworks:
  home:
    ssid: "YourHomeNetwork"
    psk: "YourHomePassword"
    priority: 100
    
  work:
    ssid: "WorkNetwork"
    psk: "WorkPassword"
    priority: 90
    
  mobile_hotspot:
    ssid: "PhoneHotspot"
    psk: "HotspotPassword"
    priority: 50
    
  guest:
    ssid: "GuestNetwork"
    # For open networks, omit psk
    priority: 10
EOF
        log_and_print "  ${GREEN}✓${NC} Created wifi.yaml.template"
        ((templates_created++))
    fi
    
    # Create environment template
    if [ ! -f "$SCRIPT_DIR/common/environment.yaml" ] && [ ! -f "$SCRIPT_DIR/common/environment.yaml.template" ]; then
        log "Creating environment.yaml.template"
        cat > "$SCRIPT_DIR/common/environment.yaml.template" <<'EOF'
# Environment Variables Template
# Copy this to environment.yaml and edit with: sops environment.yaml

# Development Tokens
NPM_TOKEN: "<PLACEHOLDER_NPM_TOKEN_IMPOSSIBLE>"
CARGO_REGISTRY_TOKEN: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Cloud Provider Credentials
AWS_ACCESS_KEY_ID: "AKIAXXXXXXXXXXXXXXXX"
AWS_SECRET_ACCESS_KEY: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Container Registry
DOCKER_HUB_TOKEN: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
GHCR_PAT: "ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Monitoring
DATADOG_API_KEY: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
SENTRY_DSN: "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX@sentry.io/XXXXXXX"
EOF
        log_and_print "  ${GREEN}✓${NC} Created environment.yaml.template"
        ((templates_created++))
    fi
    
    COMPLETED_PHASES+=("secrets_templates")
    
    if [ $templates_created -gt 0 ]; then
        log_and_print "\n${GREEN}✅ Created $templates_created template(s) in $SCRIPT_DIR/common/${NC}"
        log_and_print "  Edit templates and encrypt with: ${BOLD}sops <filename>${NC}"
    else
        log_and_print "\n${GREEN}✓ All templates already exist${NC}"
    fi
}

# Enhanced status check function
check_status() {
    log_and_print "\n${CYAN}═══════════════════════════════════════════════════════${NC}"
    log_and_print "${CYAN}                  Secrets Status Check                  ${NC}"
    log_and_print "${CYAN}═══════════════════════════════════════════════════════${NC}"
    
    # Overall health score
    local health_score=0
    local max_score=10
    
    # Check Bitwarden
    log_and_print "\n📦 ${BOLD}Bitwarden Vault Status:${NC}"
    if rbw unlocked &>/dev/null; then
        log_and_print "  ${GREEN}✓${NC} Vault is unlocked"
        ((health_score++))
        
        # Check for folders
        if rbw list --folder "Infrastructure/Age-Keys" &>/dev/null; then
            local age_count=$(rbw list --folder "Infrastructure/Age-Keys" 2>/dev/null | wc -l)
            log_and_print "  ${GREEN}✓${NC} Infrastructure/Age-Keys folder exists ($age_count items)"
            ((health_score++))
        else
            log_and_print "  ${YELLOW}⚬${NC} Infrastructure/Age-Keys folder not found"
        fi
        
        if rbw list --folder "Infrastructure/SSH-Keys" &>/dev/null; then
            local ssh_count=$(rbw list --folder "Infrastructure/SSH-Keys" 2>/dev/null | wc -l)
            log_and_print "  ${GREEN}✓${NC} Infrastructure/SSH-Keys folder exists ($ssh_count items)"
            ((health_score++))
        else
            log_and_print "  ${YELLOW}⚬${NC} Infrastructure/SSH-Keys folder not found"
        fi
    else
        log_and_print "  ${RED}✗${NC} Vault is locked or not configured"
    fi
    
    # Check local configuration
    log_and_print "\n📁 ${BOLD}Local Configuration:${NC}"
    
    # .sops.yaml
    if [ -f "$NIXCFG_ROOT/.sops.yaml" ]; then
        log_and_print "  ${GREEN}✓${NC} .sops.yaml exists"
        ((health_score++))
        
        # Check for placeholder keys
        if grep -q "PLACEHOLDER" "$NIXCFG_ROOT/.sops.yaml"; then
            log_and_print "    ${YELLOW}⚠️  Contains placeholder keys - update needed${NC}"
        else
            log_and_print "    ${GREEN}✓${NC} No placeholder keys found"
            ((health_score++))
        fi
    else
        log_and_print "  ${RED}✗${NC} .sops.yaml not found"
    fi
    
    # User age key
    if [ -f ~/.config/sops/age/keys.txt ]; then
        log_and_print "  ${GREEN}✓${NC} User age key exists"
        ((health_score++))
        local pub_key=$(age-keygen -y ~/.config/sops/age/keys.txt 2>/dev/null | cut -c1-30)
        log_and_print "    Public: ${pub_key}..."
    else
        log_and_print "  ${RED}✗${NC} User age key not found"
    fi
    
    # Host age key
    if [ -f /etc/sops/age.key ]; then
        log_and_print "  ${GREEN}✓${NC} Host age key exists ($(hostname))"
        ((health_score++))
    else
        log_and_print "  ${YELLOW}⚬${NC} Host age key not found (run deploy-age-key.sh)"
    fi
    
    # SSH keys
    if [ -f ~/.ssh/id_ed25519 ]; then
        log_and_print "  ${GREEN}✓${NC} SSH key exists for current user"
        ((health_score++))
    else
        log_and_print "  ${YELLOW}⚬${NC} No SSH key found for current user"
    fi
    
    # Secrets files
    log_and_print "\n📄 ${BOLD}Secrets Files:${NC}"
    if [ -d "$SCRIPT_DIR/common" ]; then
        local yaml_count=$(find "$SCRIPT_DIR/common" -name "*.yaml" -not -name "*.template" 2>/dev/null | wc -l)
        local template_count=$(find "$SCRIPT_DIR/common" -name "*.template" 2>/dev/null | wc -l)
        
        log_and_print "  Templates: $template_count"
        log_and_print "  Encrypted files: $yaml_count"
        
        if [ $template_count -gt 0 ]; then ((health_score++)); fi
        if [ $yaml_count -gt 0 ]; then ((health_score++)); fi
    fi
    
    # Generated files
    log_and_print "\n📋 ${BOLD}Generated Files:${NC}"
    [ -f "$SCRIPT_DIR/generated-age-public-keys.txt" ] && \
        log_and_print "  ${GREEN}✓${NC} generated-age-public-keys.txt" || \
        log_and_print "  ${YELLOW}⚬${NC} generated-age-public-keys.txt not found"
    
    [ -f "$SCRIPT_DIR/ssh-public-keys.nix" ] && \
        log_and_print "  ${GREEN}✓${NC} ssh-public-keys.nix" || \
        log_and_print "  ${YELLOW}⚬${NC} ssh-public-keys.nix not found"
    
    [ -f "$SCRIPT_DIR/deploy-ssh-keys.sh" ] && \
        log_and_print "  ${GREEN}✓${NC} deploy-ssh-keys.sh" || \
        log_and_print "  ${YELLOW}⚬${NC} deploy-ssh-keys.sh not found"
    
    # Overall health
    log_and_print "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_and_print "${BOLD}Overall Health Score: $health_score/$max_score${NC}"
    
    if [ $health_score -eq $max_score ]; then
        log_and_print "${GREEN}✅ Excellent! Everything is fully configured${NC}"
    elif [ $health_score -ge 7 ]; then
        log_and_print "${GREEN}✓ Good! Most components are configured${NC}"
    elif [ $health_score -ge 4 ]; then
        log_and_print "${YELLOW}⚬ Partial setup - continue with initialization${NC}"
    else
        log_and_print "${RED}✗ Initial setup needed - run full initialization${NC}"
    fi
    
    log "Status check complete. Health score: $health_score/$max_score"
}

# Main menu function
show_menu() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}                    Phase Selection                     ${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Choose initialization phases to run:"
    echo ""
    echo "  1) 🔐 Age Keys     - Generate age encryption keys for all hosts"
    echo "  2) 🔑 SSH Keys     - Generate/migrate SSH keys for all hosts"
    echo "  3) 📝 Secrets      - Create production secrets templates"
    echo "  4) 🚀 Full Setup   - Run all phases in sequence"
    echo "  5) 📋 Status Check - View current secrets status"
    echo "  6) 📚 Help         - Show detailed help"
    echo "  7) ❌ Exit"
    echo ""
    echo -n "Enter your choice [1-7]: "
}

# Help function
show_help() {
    echo -e "\n${BOLD}Secrets Infrastructure Initialization Help${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "${BOLD}Overview:${NC}"
    echo "  This script helps you set up a complete secrets management"
    echo "  infrastructure using Bitwarden for storage and SOPS for encryption."
    echo ""
    echo "${BOLD}Prerequisites:${NC}"
    echo "  • Bitwarden account (free tier is sufficient)"
    echo "  • Nix package manager (for installing tools)"
    echo "  • Git repository for your NixOS configuration"
    echo ""
    echo "${BOLD}Phases Explained:${NC}"
    echo ""
    echo "  ${BOLD}1. Age Keys:${NC}"
    echo "     Generates age encryption keys for each host in your"
    echo "     infrastructure. These keys are used by SOPS to encrypt"
    echo "     and decrypt secrets. Keys are stored in Bitwarden."
    echo ""
    echo "  ${BOLD}2. SSH Keys:${NC}"
    echo "     Generates or migrates SSH keys for all hosts and users."
    echo "     Creates a centralized registry of public keys for easy"
    echo "     authorized_keys management across hosts."
    echo ""
    echo "  ${BOLD}3. Secrets Templates:${NC}"
    echo "     Creates template files for common secrets like API keys,"
    echo "     WiFi passwords, and environment variables. These templates"
    echo "     can be edited and encrypted with SOPS."
    echo ""
    echo "${BOLD}Recommended Workflow:${NC}"
    echo "  1. Run Status Check to see current state"
    echo "  2. Run Full Setup for first-time initialization"
    echo "  3. Edit .sops.yaml with generated public keys"
    echo "  4. Edit secret templates and encrypt with SOPS"
    echo "  5. Deploy configurations to your hosts"
    echo ""
    echo "${BOLD}Files Created:${NC}"
    echo "  • generated-age-public-keys.txt - Reference of all public keys"
    echo "  • ssh-public-keys.nix - NixOS module with SSH keys"
    echo "  • deploy-*.sh - Scripts to deploy keys to hosts"
    echo "  • *.yaml.template - Templates for various secrets"
    echo ""
    echo "${BOLD}For more information:${NC}"
    echo "  See SECRETS-USER-INSTRUCTIONS.md for detailed steps"
    echo ""
    read -p "Press Enter to return to menu..."
}

# Ensure we're in the right directory
cd "$SCRIPT_DIR"

# Check prerequisites first
if ! check_prerequisites; then
    log_and_print "${RED}Prerequisites check failed. Please resolve issues and try again.${NC}"
    exit 1
fi

# Main loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            check_bitwarden && run_age_keys
            ;;
        2)
            check_bitwarden && run_ssh_keys
            ;;
        3)
            run_secrets_templates
            ;;
        4)
            log_and_print "\n${BOLD}Starting Full Setup${NC}"
            preview_actions "full" || continue
            
            check_bitwarden || continue
            
            run_age_keys
            [ $? -eq 0 ] && log_and_print "\n${GREEN}✓ Phase 1 complete${NC}" || log_and_print "\n${YELLOW}⚠ Phase 1 had issues${NC}"
            
            echo -e "\n${BOLD}Press Enter to continue with SSH keys...${NC}"
            read -r
            
            run_ssh_keys
            [ $? -eq 0 ] && log_and_print "\n${GREEN}✓ Phase 2 complete${NC}" || log_and_print "\n${YELLOW}⚠ Phase 2 had issues${NC}"
            
            echo -e "\n${BOLD}Press Enter to continue with secrets templates...${NC}"
            read -r
            
            run_secrets_templates
            [ $? -eq 0 ] && log_and_print "\n${GREEN}✓ Phase 3 complete${NC}" || log_and_print "\n${YELLOW}⚠ Phase 3 had issues${NC}"
            
            # Final status
            log_and_print "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
            if [ ${#FAILED_PHASES[@]} -eq 0 ]; then
                log_and_print "${GREEN}           ✅ Full Setup Complete!                      ${NC}"
            else
                log_and_print "${YELLOW}      ⚠️  Setup completed with some issues              ${NC}"
                log_and_print "${YELLOW}      Failed phases: ${FAILED_PHASES[*]}              ${NC}"
            fi
            log_and_print "${GREEN}═══════════════════════════════════════════════════════${NC}"
            
            check_status
            ;;
        5)
            check_status
            ;;
        6)
            show_help
            ;;
        7)
            log "User exited"
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please select 1-7.${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}Press Enter to continue...${NC}"
    read -r
done
