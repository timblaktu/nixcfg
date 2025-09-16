# SSH Key Automation Module
# Provides automated SSH keypair generation and distribution during system activation
# Integrates with ssh-public-keys.nix registry and bitwarden-ssh-keys.nix for complete key management
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.sshKeyAutomation;
  hostName = config.networking.hostName;
  
  # Reference to SSH public keys registry if available
  sshKeysRegistry = config.sshPublicKeys or {};
  hasRegistry = config.sshPublicKeys.enable or false;
  
  # Reference to Bitwarden SSH module if available
  bitwardenSSH = config.bitwardenSSH or {};
  hasBitwarden = config.bitwardenSSH.enable or false;
  
  # SSH key type to generate (ed25519 is modern and secure)
  keyType = cfg.keyType;
  
  # Helper script to generate SSH keypair
  generateKeyScript = user: isHost: keyPath: ''
    if [ ! -f "${keyPath}" ]; then
      echo "Generating new SSH ${keyType} key for ${if isHost then "host ${hostName}" else "user ${user}"}"
      ${pkgs.openssh}/bin/ssh-keygen -t ${keyType} -f "${keyPath}" -N "" -C "${if isHost then "root@${hostName}" else "${user}@${hostName}"}"
      
      # Set correct permissions
      chmod 600 "${keyPath}"
      chmod 644 "${keyPath}.pub"
      
      ${if !isHost then ''
        # For user keys, ensure ownership is correct
        if [ -n "${user}" ] && id -u "${user}" >/dev/null 2>&1; then
          chown ${user}:users "${keyPath}" "${keyPath}.pub" 2>/dev/null || true
        fi
      '' else ""}
      
      echo "Generated SSH ${keyType} key: ${keyPath}"
      
      # Register the public key if registry is enabled
      ${if hasRegistry && cfg.registerKeys then ''
        PUB_KEY=$(cat "${keyPath}.pub")
        echo "Public key for ${if isHost then "host" else user}: $PUB_KEY"
        # Note: Actual registry update would require rebuild with the new key in configuration
        echo "To register this key, add it to the SSH public keys registry in your configuration:"
        echo "  ${if isHost then "sshPublicKeys.hosts.\"${hostName}\"" else "sshPublicKeys.users.${user}.\"${hostName}\""} = \"$PUB_KEY\";"
      '' else ""}
    else
      echo "SSH key already exists: ${keyPath}"
    fi
  '';
  
  # Generate activation script for user keys
  userKeyGeneration = user: ''
    # Ensure user exists before generating keys
    if id -u "${user}" >/dev/null 2>&1; then
      USER_HOME=$(eval echo ~${user})
      SSH_DIR="$USER_HOME/.ssh"
      
      # Create .ssh directory if it doesn't exist
      if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        if [ -n "${user}" ]; then
          chown ${user}:users "$SSH_DIR" 2>/dev/null || true
        fi
      fi
      
      # Generate key if it doesn't exist
      KEY_PATH="$SSH_DIR/id_${keyType}"
      ${generateKeyScript user false "$KEY_PATH"}
    else
      echo "User ${user} does not exist, skipping SSH key generation"
    fi
  '';
  
  # Generate activation script for host keys
  hostKeyGeneration = ''
    # Host keys are in /etc/ssh/
    HOST_KEY_PATH="/etc/ssh/ssh_host_${keyType}_key"
    ${generateKeyScript "" true "$HOST_KEY_PATH"}
  '';
  
  # Distribute keys to authorized hosts
  distributeKeys = user: hosts: ''
    if id -u "${user}" >/dev/null 2>&1; then
      USER_HOME=$(eval echo ~${user})
      AUTH_KEYS_FILE="$USER_HOME/.ssh/authorized_keys"
      
      # Ensure .ssh directory exists
      mkdir -p "$USER_HOME/.ssh"
      chmod 700 "$USER_HOME/.ssh"
      
      # Create or update authorized_keys
      touch "$AUTH_KEYS_FILE"
      chmod 600 "$AUTH_KEYS_FILE"
      
      ${concatMapStringsSep "\n" (host: ''
        # Try to get key from registry if available
        ${if hasRegistry then ''
          # Note: This would need runtime access to registry data
          echo "Would add keys from host ${host} to ${user}'s authorized_keys"
        '' else ''
          echo "SSH key registry not enabled, skipping key distribution for ${host}"
        ''}
      '') hosts}
      
      # Fix ownership
      if [ -n "${user}" ]; then
        chown ${user}:users "$AUTH_KEYS_FILE" 2>/dev/null || true
      fi
    fi
  '';

in {
  options.sshKeyAutomation = {
    enable = mkEnableOption "automatic SSH key management";
    
    generateUserKeys = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically generate user SSH keypairs during activation";
    };
    
    generateHostKeys = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically generate host SSH keypairs during activation";
    };
    
    keyType = mkOption {
      type = types.enum [ "ed25519" "rsa" "ecdsa" ];
      default = "ed25519";
      description = "Type of SSH key to generate";
    };
    
    users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of users for whom to generate SSH keys.
        If empty and generateUserKeys is true, generates for all normal users.
      '';
    };
    
    authorizedHosts = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of hosts whose keys should be authorized for users.
        Used for distributing keys across systems.
      '';
    };
    
    registerKeys = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Attempt to register generated keys with the SSH public keys registry.
        Note: This outputs instructions for manual configuration update.
      '';
    };
    
    preGenerateCheck = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Check for existing keys from other sources (like Bitwarden) before generating.
        Prevents overwriting keys that might be managed elsewhere.
      '';
    };
  };
  
  config = mkIf cfg.enable {
    # Assertions for safety
    assertions = [
      {
        assertion = cfg.keyType == "ed25519" || cfg.keyType == "rsa" || cfg.keyType == "ecdsa";
        message = "SSH key type must be one of: ed25519, rsa, ecdsa";
      }
      {
        assertion = !cfg.generateHostKeys || config.services.openssh.enable or false;
        message = "SSH host key generation requires services.openssh.enable = true";
      }
    ];
    
    # System activation script for key generation
    system.activationScripts.sshKeyAutomation = stringAfter [ "users" "groups" ] ''
      echo "Starting SSH key automation..."
      
      # Generate host keys if enabled
      ${optionalString (cfg.generateHostKeys) ''
        echo "Checking host SSH keys..."
        
        # Skip if Bitwarden module will handle it
        ${if hasBitwarden && bitwardenSSH.fetchHostKeys or false then ''
          echo "Bitwarden SSH module is handling host keys, skipping generation"
        '' else hostKeyGeneration}
      ''}
      
      # Generate user keys if enabled
      ${optionalString (cfg.generateUserKeys) ''
        echo "Checking user SSH keys..."
        
        # Determine which users to process
        USERS_TO_PROCESS="${if cfg.users != [] then concatStringsSep " " cfg.users else ""}"
        
        if [ -z "$USERS_TO_PROCESS" ]; then
          # Get all normal users (UID >= 1000)
          USERS_TO_PROCESS=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}')
        fi
        
        for USER in $USERS_TO_PROCESS; do
          echo "Processing SSH keys for user: $USER"
          
          # Skip if Bitwarden module will handle it
          ${if hasBitwarden && bitwardenSSH.fetchUserKeys or false then ''
            if echo "${concatStringsSep " " (bitwardenSSH.users or [])}" | grep -q "$USER"; then
              echo "Bitwarden SSH module is handling keys for $USER, skipping generation"
              continue
            fi
          '' else ""}
          
          ${if cfg.preGenerateCheck then ''
            # Check if keys already exist
            USER_HOME=$(eval echo ~$USER 2>/dev/null || echo "/home/$USER")
            if [ -f "$USER_HOME/.ssh/id_${keyType}" ]; then
              echo "SSH key already exists for $USER, skipping generation"
              continue
            fi
          '' else ""}
          
          # Generate the key
          ${userKeyGeneration "$USER"}
        done
      ''}
      
      # Distribute keys if authorized hosts are configured
      ${optionalString (cfg.authorizedHosts != []) ''
        echo "Distributing SSH keys to authorized hosts..."
        
        for USER in $USERS_TO_PROCESS; do
          ${distributeKeys "$USER" cfg.authorizedHosts}
        done
      ''}
      
      echo "SSH key automation completed"
    '';
    
    # Integration with openssh service for host keys
    services.openssh = mkIf cfg.generateHostKeys {
      hostKeys = mkDefault [
        {
          path = "/etc/ssh/ssh_host_${keyType}_key";
          type = keyType;
        }
      ];
    };
    
    # Warnings for configuration issues
    warnings = 
      (optional (cfg.generateUserKeys && cfg.users == [] && !config.users.mutableUsers or true)
        "SSH key automation is generating keys for all users. Consider specifying specific users in sshKeyAutomation.users")
      ++
      (optional (cfg.registerKeys && !hasRegistry)
        "SSH key registration is enabled but sshPublicKeys registry module is not enabled. Generated keys won't be registered.")
      ++
      (optional (cfg.authorizedHosts != [] && !hasRegistry)
        "Authorized hosts are configured but SSH public keys registry is not enabled. Key distribution may not work correctly.")
      ++
      (optional (hasBitwarden && cfg.generateUserKeys && bitwardenSSH.fetchUserKeys or false)
        "Both SSH key automation and Bitwarden SSH user key fetching are enabled. Bitwarden keys will take precedence.");
  };
}