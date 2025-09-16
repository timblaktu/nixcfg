# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ../../modules/base.nix
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
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
    hostname = "tblack-t14-nixos";
    defaultUser = "tim";
    sshPort = 22;
    userGroups = [ "wheel" "dialout" ];
    enableWindowsTools = true;
  };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
