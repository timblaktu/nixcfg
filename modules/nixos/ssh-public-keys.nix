# SSH Public Keys Registry Module
# Central registry for SSH public keys with validation and distribution
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.sshPublicKeys;
  
  # SSH key format validation
  sshKeyType = types.strMatching "^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]+(=*)( .*)?$";
  
  # Key registry structure types
  userKeysType = types.attrsOf (types.attrsOf sshKeyType);
  hostKeysType = types.attrsOf sshKeyType;
  
  # Validation functions
  validateKeyUniqueness = keys: 
    let
      allKeys = flatten (mapAttrsToList (host: hostKeys: 
        mapAttrsToList (user: key: key) hostKeys
      ) keys.users) ++ (mapAttrsToList (host: key: key) keys.hosts);
      uniqueKeys = unique allKeys;
    in length allKeys == length uniqueKeys;
    
  # Helper functions for key extraction
  getUserKeys = user: host: 
    if cfg.users ? ${user} && cfg.users.${user} ? ${host}
    then cfg.users.${user}.${host}
    else null;
    
  getAllUserKeys = user:
    if cfg.users ? ${user}
    then attrValues cfg.users.${user}
    else [];
    
  getHostKey = host:
    if cfg.hosts ? ${host}
    then cfg.hosts.${host}
    else null;
    
  # Integration helpers for authorized_keys distribution
  distributeUserKeys = user: hosts:
    flatten (map (host: 
      let key = getUserKeys user host;
      in if key != null then [key] else []
    ) hosts);
    
  distributeAllUserKeys = user:
    if cfg.users ? ${user}
    then attrValues cfg.users.${user}
    else [];

in {
  options.sshPublicKeys = {
    enable = mkEnableOption "SSH public keys registry";
    
    users = mkOption {
      type = userKeysType;
      default = {};
      description = ''
        Registry of SSH public keys for users across different hosts.
        Structure: users.<username>.<hostname> = "ssh-ed25519 AAAA... user@host"
      '';
      example = literalExpression ''
        {
          tim = {
            "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tim@thinky-nixos";
            "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tim@potato";
            "mbp" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tim@mbp";
          };
        }
      '';
    };
    
    hosts = mkOption {
      type = hostKeysType;
      default = {};
      description = ''
        Registry of SSH host public keys.
        Structure: hosts.<hostname> = "ssh-ed25519 AAAA... root@hostname"
      '';
      example = literalExpression ''
        {
          "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... root@thinky-nixos";
          "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... root@potato";
        }
      '';
    };
    
    autoDistribute = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically distribute registered keys to users' authorized_keys.
        When enabled, all registered user keys are added to each user's authorized_keys.
      '';
    };
    
    distributionHosts = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of hosts whose keys should be distributed for cross-host authentication.
        If empty, all registered hosts are included.
      '';
    };
    
    restrictedUsers = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {};
      description = ''
        Override auto-distribution for specific users.
        Maps username to list of hostnames whose keys should be authorized.
      '';
      example = literalExpression ''
        {
          admin = [ "thinky-nixos" "potato" ];  # Admin only gets these two hosts
          guest = [ "thinky-nixos" ];          # Guest only gets thinky-nixos
        }
      '';
    };
  };
  
  config = mkIf cfg.enable {
    # Runtime assertions for validation
    assertions = [
      {
        assertion = validateKeyUniqueness cfg;
        message = "Duplicate SSH keys found in registry. Each key must be unique across all users and hosts.";
      }
      {
        assertion = all (user: user != "") (attrNames cfg.users);
        message = "User names in SSH key registry cannot be empty.";
      }
      {
        assertion = all (host: host != "") (attrNames cfg.hosts);
        message = "Host names in SSH key registry cannot be empty.";
      }
      {
        assertion = all (user: 
          all (host: host != "") (attrNames cfg.users.${user})
        ) (attrNames cfg.users);
        message = "Host names in user SSH key registry cannot be empty.";
      }
    ];
    
    # Integration functions exposed for other modules
    _sshKeyRegistry = {
      # Core functions for key retrieval
      getUserKey = getUserKeys;
      getAllUserKeys = getAllUserKeys;
      getHostKey = getHostKey;
      
      # Distribution functions for authorized_keys integration
      distributeUserKeys = distributeUserKeys;
      distributeAllUserKeys = distributeAllUserKeys;
      
      # Registry access
      allUsers = attrNames cfg.users;
      allHosts = attrNames cfg.hosts;
      registry = cfg;
    };
    
    # Auto-distribution of keys to users' authorized_keys
    users.users = mkIf cfg.autoDistribute (
      let
        # Determine which hosts to include for each user
        getDistributionHosts = user:
          if cfg.restrictedUsers ? ${user}
          then cfg.restrictedUsers.${user}
          else if cfg.distributionHosts != []
          then cfg.distributionHosts  
          else (attrNames cfg.hosts);
          
        # Filter to only existing users
        existingUsers = filter (user: 
          config.users.users ? ${user}
        ) (attrNames cfg.users);
        
        # Generate authorized keys for each existing registered user
        userConfigs = listToAttrs (map (user: {
          name = user;
          value = {
            openssh.authorizedKeys.keys = mkDefault (
              distributeUserKeys user (getDistributionHosts user)
            );
          };
        }) existingUsers);
        
      in userConfigs
    );
    
    # Warnings for common configuration issues
    warnings = 
      let
        emptyUsers = filter (user: cfg.users.${user} == {}) (attrNames cfg.users);
        singleKeyUsers = filter (user: 
          length (attrNames cfg.users.${user}) == 1
        ) (attrNames cfg.users);
        nonExistentUsers = filter (user:
          !(config.users.users ? ${user})
        ) (attrNames cfg.users);
      in
      (optional (emptyUsers != []) 
        "SSH key registry has users with no keys: ${concatStringsSep ", " emptyUsers}")
      ++
      (optional (cfg.hosts == {}) 
        "SSH key registry has no host keys registered. Consider adding host keys for complete setup.")
      ++
      (optional (singleKeyUsers != [] && length (attrNames cfg.users) > 1)
        "Some users have only one host key: ${concatStringsSep ", " singleKeyUsers}. This may indicate incomplete key distribution.")
      ++
      (optional (nonExistentUsers != [] && cfg.autoDistribute)
        "SSH key registry has keys for non-existent users (keys will not be distributed): ${concatStringsSep ", " nonExistentUsers}");
  };
}