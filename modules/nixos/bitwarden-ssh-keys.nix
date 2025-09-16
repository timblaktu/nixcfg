# Bitwarden SSH Keys Module
# Manages SSH key deployment from Bitwarden using rbw CLI
# Integrates with ssh-public-keys.nix registry and bootstrap-ssh-keys.sh script
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.bitwardenSSH;
  
  # Reference to SSH public keys registry if available
  sshKeysRegistry = config.sshPublicKeys or {};
  
  # Bootstrap script location (assumes it's in user's PATH via home-manager)
  bootstrapScript = "bootstrap-ssh-keys.sh";
  
  # Helper to create activation script for a specific user
  mkUserKeyFetchScript = user: ''
    echo "Fetching SSH keys for user ${user}..."
    if [ -d /home/${user} ]; then
      # Run as the target user
      sudo -u ${user} bash -c '
        # Check if rbw is available and unlocked
        if command -v rbw >/dev/null 2>&1; then
          if rbw unlocked 2>/dev/null; then
            # Use bootstrap script if available, otherwise direct rbw fetch
            if command -v ${bootstrapScript} >/dev/null 2>&1; then
              echo "Using bootstrap script for ${user}..."
              ${bootstrapScript} --user ${user} --host ${config.networking.hostName} ${optionalString cfg.verbose "--verbose"} ${optionalString cfg.quiet "--quiet"}
            else
              # Fallback to direct rbw fetch
              SSH_KEY_NAME="ssh-user-${user}@${config.networking.hostName}"
              KEY_CONTENT=$(rbw get -f notes "$SSH_KEY_NAME" 2>/dev/null || true)
              
              if [ -n "$KEY_CONTENT" ]; then
                mkdir -p ~/.ssh
                chmod 700 ~/.ssh
                
                # Extract and deploy private key
                echo "$KEY_CONTENT" | sed -n "/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p" > ~/.ssh/id_${cfg.keyType}
                chmod 600 ~/.ssh/id_${cfg.keyType}
                
                # Extract and deploy public key
                echo "$KEY_CONTENT" | grep "^ssh-${cfg.keyType}" > ~/.ssh/id_${cfg.keyType}.pub 2>/dev/null || \
                  echo "$KEY_CONTENT" | grep "^ssh-" > ~/.ssh/id_${cfg.keyType}.pub
                chmod 644 ~/.ssh/id_${cfg.keyType}.pub
                
                echo "SSH keys for ${user} deployed from Bitwarden"
              else
                echo "No SSH keys found in Bitwarden for ${user}@${config.networking.hostName}"
              fi
            fi
          else
            echo "rbw is locked. Skipping SSH key fetch for ${user}."
            echo "To unlock: rbw unlock"
          fi
        else
          echo "rbw not found. Cannot fetch SSH keys for ${user}."
        fi
      '
    else
      echo "User ${user} home directory does not exist. Skipping."
    fi
  '';
  
  # Helper to create host key fetch script
  mkHostKeyFetchScript = ''
    echo "Fetching SSH host keys..."
    
    # Must run as root for host keys
    if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
      # Check if rbw is available and configured for root
      if command -v rbw >/dev/null 2>&1; then
        # Try to run rbw as configured admin user if set
        ${if cfg.adminUser != null then ''
          if sudo -u ${cfg.adminUser} rbw unlocked 2>/dev/null; then
            HOST_KEY_NAME="ssh-host-${config.networking.hostName}"
            KEY_CONTENT=$(sudo -u ${cfg.adminUser} rbw get -f notes "$HOST_KEY_NAME" 2>/dev/null || true)
            
            if [ -n "$KEY_CONTENT" ]; then
              # Deploy host keys to /etc/ssh/
              echo "$KEY_CONTENT" | sed -n "/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p" > /etc/ssh/ssh_host_${cfg.keyType}_key
              chmod 600 /etc/ssh/ssh_host_${cfg.keyType}_key
              
              echo "$KEY_CONTENT" | grep "^ssh-${cfg.keyType}" > /etc/ssh/ssh_host_${cfg.keyType}_key.pub 2>/dev/null || \
                echo "$KEY_CONTENT" | grep "^ssh-" > /etc/ssh/ssh_host_${cfg.keyType}_key.pub
              chmod 644 /etc/ssh/ssh_host_${cfg.keyType}_key.pub
              
              echo "SSH host keys deployed from Bitwarden"
            else
              echo "No SSH host keys found in Bitwarden for ${config.networking.hostName}"
            fi
          else
            echo "rbw is locked for admin user ${cfg.adminUser}. Skipping host key fetch."
          fi
        '' else ''
          echo "No admin user configured for host key fetching. Set bitwardenSSH.adminUser."
        ''}
      else
        echo "rbw not found. Cannot fetch SSH host keys."
      fi
    else
      echo "Host key deployment requires root privileges."
    fi
  '';

in {
  options.bitwardenSSH = {
    enable = mkEnableOption "Bitwarden-based SSH key management";
    
    fetchUserKeys = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Fetch user SSH keys from Bitwarden on system activation.
        Keys are fetched using rbw CLI and deployed to user's ~/.ssh directory.
      '';
    };
    
    fetchHostKeys = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Fetch host SSH keys from Bitwarden on system activation.
        This is more sensitive and requires admin privileges.
        Host keys are deployed to /etc/ssh/.
      '';
    };
    
    users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of users to fetch SSH keys for.
        Each user must have rbw configured and unlocked.
      '';
      example = [ "tim" "admin" ];
    };
    
    adminUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Admin user account to use for fetching host keys.
        This user must have rbw configured with access to host keys in Bitwarden.
      '';
      example = "tim";
    };
    
    keyType = mkOption {
      type = types.enum [ "ed25519" "rsa" "ecdsa" ];
      default = "ed25519";
      description = ''
        SSH key type to use. Must match the keys stored in Bitwarden.
      '';
    };
    
    bitwarden = {
      folder = mkOption {
        type = types.str;
        default = "Infrastructure/SSH-Keys";
        description = ''
          Bitwarden folder containing SSH keys.
          Used by the bootstrap script.
        '';
      };
      
      userKeyPrefix = mkOption {
        type = types.str;
        default = "ssh-user-";
        description = ''
          Prefix for user SSH key names in Bitwarden.
          Full name format: <prefix><username>@<hostname>
        '';
      };
      
      hostKeyPrefix = mkOption {
        type = types.str;
        default = "ssh-host-";
        description = ''
          Prefix for host SSH key names in Bitwarden.
          Full name format: <prefix><hostname>
        '';
      };
    };
    
    autoRegister = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically register fetched public keys to the SSH public keys registry.
        Requires sshPublicKeys module to be enabled.
      '';
    };
    
    verbose = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable verbose output during key fetching operations.
      '';
    };
    
    quiet = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Suppress non-error output during key fetching operations.
      '';
    };
    
    forceRegenerate = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Force regeneration of SSH keys even if they exist.
        WARNING: This will overwrite existing keys.
      '';
    };
  };
  
  config = mkIf cfg.enable {
    # Ensure rbw is available system-wide
    environment.systemPackages = with pkgs; [
      rbw
      openssh  # For ssh-keygen if bootstrap needs to generate keys
    ];
    
    # User key fetching activation script
    system.activationScripts.fetchUserSSHKeys = mkIf cfg.fetchUserKeys (
      stringAfter [ "users" "groups" ] (
        concatMapStrings mkUserKeyFetchScript cfg.users
      )
    );
    
    # Host key fetching activation script
    system.activationScripts.fetchHostSSHKeys = mkIf cfg.fetchHostKeys (
      stringAfter [ "users" "groups" ] mkHostKeyFetchScript
    );
    
    # Integration with SSH public keys registry
    # This dynamically updates the registry with keys found in Bitwarden
    system.activationScripts.registerBitwardenKeys = mkIf (cfg.autoRegister && config.sshPublicKeys.enable or false) (
      stringAfter [ "fetchUserSSHKeys" "fetchHostSSHKeys" ] ''
        echo "Registering Bitwarden SSH keys in public keys registry..."
        
        # Note: Actual registration would require runtime modification of the registry
        # This is a placeholder for future implementation that might write to a state file
        # that the ssh-public-keys module can read
        
        ${concatMapStrings (user: ''
          if [ -f /home/${user}/.ssh/id_${cfg.keyType}.pub ]; then
            echo "Found public key for ${user}@${config.networking.hostName}"
            # Future: Write to registry state file
          fi
        '') cfg.users}
        
        ${optionalString cfg.fetchHostKeys ''
          if [ -f /etc/ssh/ssh_host_${cfg.keyType}_key.pub ]; then
            echo "Found host public key for ${config.networking.hostName}"
            # Future: Write to registry state file
          fi
        ''}
      ''
    );
    
    # Ensure SSH service is configured to use the deployed host keys
    services.openssh = mkIf cfg.fetchHostKeys {
      hostKeys = mkDefault [
        {
          path = "/etc/ssh/ssh_host_${cfg.keyType}_key";
          type = cfg.keyType;
        }
      ];
    };
    
    # Warnings for common configuration issues
    warnings = 
      (optional (cfg.fetchHostKeys && cfg.adminUser == null)
        "bitwardenSSH.fetchHostKeys is enabled but bitwardenSSH.adminUser is not set. Host key fetching will fail.")
      ++
      (optional (cfg.users == [] && cfg.fetchUserKeys)
        "bitwardenSSH.fetchUserKeys is enabled but no users are specified in bitwardenSSH.users.")
      ++
      (optional (cfg.autoRegister && !(config.sshPublicKeys.enable or false))
        "bitwardenSSH.autoRegister is enabled but sshPublicKeys module is not enabled. Keys won't be registered.");
    
    # Assertions for critical configuration requirements
    assertions = [
      {
        assertion = cfg.fetchHostKeys -> cfg.adminUser != null;
        message = "bitwardenSSH.fetchHostKeys requires bitwardenSSH.adminUser to be set";
      }
      {
        assertion = cfg.fetchUserKeys -> cfg.users != [];
        message = "bitwardenSSH.fetchUserKeys requires at least one user in bitwardenSSH.users";
      }
    ];
  };
}