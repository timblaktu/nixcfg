# Example Bitwarden SSH Keys Configuration
# This file demonstrates how to integrate the Bitwarden SSH keys module
# with the SSH public keys registry for automated key management.
#
# Prerequisites:
# 1. rbw CLI installed and configured (handled by home-manager secrets-management.nix)
# 2. Bitwarden vault unlocked: rbw unlock
# 3. SSH keys stored in Bitwarden with proper naming convention
# 4. bootstrap-ssh-keys.sh script available in PATH (from home-manager)
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/nixos/ssh-public-keys.nix
    ../../modules/nixos/bitwarden-ssh-keys.nix
  ];
  
  # Bitwarden SSH Key Management Configuration
  bitwardenSSH = {
    enable = true;  # Enable Bitwarden-based SSH key management
    
    # User key management
    fetchUserKeys = true;  # Fetch user SSH keys on system activation
    users = [ "tim" ];     # Users to fetch keys for (must have rbw configured)
    
    # Host key management (more sensitive, disabled by default)
    fetchHostKeys = false;   # Set to true to manage host SSH keys
    adminUser = "tim";       # Admin user with rbw access for host keys
    
    # Key configuration
    keyType = "ed25519";     # SSH key type (must match stored keys)
    
    # Bitwarden organization
    bitwarden = {
      folder = "Infrastructure/SSH-Keys";  # Folder containing SSH keys
      userKeyPrefix = "ssh-user-";        # User key naming prefix
      hostKeyPrefix = "ssh-host-";        # Host key naming prefix
    };
    
    # Integration options
    autoRegister = true;     # Register fetched keys in SSH public keys registry
    
    # Output control
    verbose = false;         # Enable verbose output
    quiet = false;          # Suppress non-error output
    forceRegenerate = false; # Force key regeneration (WARNING: overwrites existing)
  };
  
  # SSH Public Keys Registry Configuration
  # This works alongside Bitwarden SSH to maintain a registry of all keys
  sshPublicKeys = {
    enable = true;  # Enable the SSH public keys registry
    
    # Static key entries (can be used alongside Bitwarden-fetched keys)
    users = {
      tim = {
        # These can be manually added or will be populated by Bitwarden
        # The Bitwarden module will attempt to register fetched keys here
        # "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@thinky-nixos";
      };
    };
    
    # Host keys registry
    hosts = {
      # Host keys can be manually added or fetched from Bitwarden
      # "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@thinky-nixos";
    };
    
    # Auto-distribution of keys to authorized_keys
    autoDistribute = true;
    
    # Optional: Limit distribution to specific hosts
    # distributionHosts = [ "thinky-nixos" "potato" ];
    
    # Optional: Restrict keys for specific users
    # restrictedUsers = {
    #   guest = [ "thinky-nixos" ];  # Guest only gets one host's key
    # };
  };
  
  # Usage Notes:
  # 1. Initial Setup:
  #    - Ensure rbw is configured: rbw config set email your.email@example.com
  #    - Login to Bitwarden: rbw login
  #    - Unlock vault: rbw unlock
  #
  # 2. Key Naming Convention in Bitwarden:
  #    User keys: ssh-user-<username>@<hostname>
  #    Host keys: ssh-host-<hostname>
  #
  # 3. Key Storage Format in Bitwarden:
  #    Store the full key content (private + public) in the notes field
  #    The module will extract the appropriate parts
  #
  # 4. Bootstrap Script:
  #    The module uses bootstrap-ssh-keys.sh if available
  #    This script can generate keys if they don't exist in Bitwarden
  #    Run manually: bootstrap-ssh-keys.sh --user tim --host thinky-nixos
  #
  # 5. System Activation:
  #    Keys are fetched/deployed during nixos-rebuild switch
  #    Only runs if rbw is unlocked
  #
  # 6. Security Considerations:
  #    - User keys require the user to have rbw configured and unlocked
  #    - Host keys require admin privileges and are more sensitive
  #    - Keys are only fetched if rbw is unlocked (no automatic unlock)
  #    - Private keys are deployed with proper permissions (600)
}