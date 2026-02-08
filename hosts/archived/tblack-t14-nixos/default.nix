# WSL NixOS configuration (archived)
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    # Dendritic system type - provides system-cli layer (includes default and minimal)
    inputs.self.modules.nixos.system-cli
    ../../../modules/wsl-common.nix
    ../../../modules/wsl-tarball-checks.nix
  ];

  # Minimal layer configuration (1-minimal)
  systemMinimal = {
    nixMaxJobs = 8;
    nixCores = 0;
    enableBinaryCache = true;
    cacheTimeout = 10;
  };

  # Default layer configuration (2-default)
  systemDefault = {
    userName = "tim";
    userGroups = [ "wheel" "dialout" ];
    extraShellAliases = {
      esp32c5 = "esp-idf-shell";
    };
  };

  # CLI layer configuration (3-cli)
  systemCli = {
    enableClaudeCodeEnterprise = true;
    enablePodman = true;
  };

  # WSL common configuration
  wslCommon = {
    enable = true;
    hostname = "tblack-t14-nixos";
    defaultUser = "tim";
    sshPort = 22;
    userGroups = [ "wheel" "dialout" ];
    enableWindowsTools = true;
  };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
