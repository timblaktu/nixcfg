# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ../../modules/base.nix
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
    ../../modules/nixos/sops-nix.nix
  ];
  
  # Base module configuration
  base = {
    userName = "tim";
    userGroups = [ "wheel" "dialout" ];
    enableClaudeCodeEnterprise = true;
    nixMaxJobs = 8;
    nixCores = 0;
    enableBinaryCache = true;
    cacheTimeout = 10;
    additionalShellAliases = {
      esp32c5 = "esp-idf-shell";
    };
  };

  # WSL common configuration
  wslCommon = {
    enable = true;
    hostname = "thinky-nixos";
    defaultUser = "tim";
    sshPort = 2223;  # Must bind to unique port since sharing winHost with another WSL guest
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com"
    ];
    enableWindowsTools = true;
  };

  # SOPS-NiX configuration for secrets management
  sopsNix = {
    enable = true;
    hostKeyPath = "/etc/sops/age.key";
    # defaultSopsFile will be set when we have production secrets
  };
  
  # Production secrets will be defined here as needed
  # Example:
  # sops.secrets = {
  #   "github_token" = {
  #     owner = "tim";
  #     group = "users";
  #     mode = "0400";
  #     sopsFile = ../../secrets/common/services.yaml;
  #   };
  # };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
