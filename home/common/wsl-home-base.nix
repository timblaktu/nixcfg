# Common home-manager configuration for WSL environments
# Provides sensible defaults for WSL development setup
{ config, lib, pkgs, ... }:

{
  # Standard homeBase configuration for WSL
  homeBase = {
    enableDevelopment = lib.mkDefault true;
    enableEspIdf = lib.mkDefault true;
    enableOneDriveUtils = lib.mkDefault true;
    enableShellUtils = lib.mkDefault true;
    enableTerminal = lib.mkDefault true;

    environmentVariables = {
      WSL_DISTRO = lib.mkDefault "nixos";
      EDITOR = lib.mkDefault "nvim";
    };

    shellAliases = {
      explorer = lib.mkDefault "explorer.exe .";
      code = lib.mkDefault "code.exe";
      code-insiders = lib.mkDefault "code-insiders.exe";
      esp32c5 = lib.mkDefault "esp-idf-shell";
    };
  };

  # WSL utilities
  home.packages = with pkgs; [
    wslu
  ];

  # WSL target configuration
  targets.wsl = {
    enable = true;
    windowsTools = {
      enablePowerShell = lib.mkDefault true;
      enableCmd = lib.mkDefault false;
      enableWslPath = lib.mkDefault true;
      wslPathPath = lib.mkDefault "/bin/wslpath";
    };
  };
}
