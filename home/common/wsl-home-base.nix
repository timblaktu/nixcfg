# Common home-manager configuration for WSL environments (Home Manager Module)
#
# PLATFORM REQUIREMENTS: ANY WSL distribution + Nix + home-manager ✅
# This is a Home Manager user configuration module that works on ANY WSL distribution
# where Nix and home-manager are installed (NixOS-WSL, Ubuntu, Debian, Alpine, etc.)
#
# PROVIDES:
# - User-level WSL tweaks (shell wrappers, environment variables)
# - Windows Terminal settings management (via targets.wsl)
# - WSL utilities (wslu package)
# - Home Manager targets.wsl configuration
#
# USE CASES:
# - thinky-nixos (NixOS-WSL host) - home-manager config
# - pa161878-nixos (NixOS-WSL host) - home-manager config
# - Colleague on vanilla Ubuntu WSL - portable config! ✅
# - Any other WSL distribution with Nix + home-manager installed
#
# FOR SYSTEM-LEVEL WSL CONFIG (NixOS-WSL only):
# See hosts/common/wsl-base.nix - that's a NixOS system module that requires
# a full NixOS-WSL distribution and provides system-level integration.
#
# USAGE: Import this in WSL home-manager configs to get standard WSL user setup
#
# NOTE: wslu appears in both this module and hosts/common/wsl-base.nix
# This is intentional - system-wide on NixOS-WSL, user-level on vanilla WSL.
# Nix automatically deduplicates on NixOS-WSL, and it's essential for portability.
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
