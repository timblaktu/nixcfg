# SOPS-NiX module for secrets management
{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.sopsNix;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];
  
  options.sopsNix = {
    enable = mkEnableOption "SOPS-NiX secrets management";
    
    hostKeyPath = mkOption {
      type = types.str;
      default = "/etc/sops/age.key";
      description = "Path to the host's age private key";
    };
    
    defaultSopsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Default SOPS file for secrets";
    };
  };

  config = mkIf cfg.enable {
    # Configure SOPS
    sops = {
      # Use the host's age key for decryption
      age.keyFile = cfg.hostKeyPath;
      
      # Set default SOPS file if provided
      defaultSopsFile = mkIf (cfg.defaultSopsFile != null) cfg.defaultSopsFile;
      
      # Ensure secrets are available at activation time
      gnupg.sshKeyPaths = [];
    };
    
    # Ensure the host key directory exists with proper permissions
    systemd.tmpfiles.rules = [
      "d /etc/sops 0755 root root -"
    ];
  };
}