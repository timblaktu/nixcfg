# Common WSL host configuration base (NixOS System Module)
#
# PLATFORM REQUIREMENTS: NixOS-WSL distribution ONLY
# This is a NixOS system configuration module that requires a full NixOS-WSL distribution.
# It CANNOT be used on vanilla Ubuntu/Debian/Alpine WSL installations.
#
# PROVIDES:
# - System-level WSL integration (wsl.conf, systemd services)
# - User and group management via NixOS
# - SSH daemon configuration with WSL-specific settings
# - SOPS-nix secrets management
# - NixOS-WSL module imports
#
# USE CASES:
# - thinky-nixos (NixOS-WSL host)
# - pa161878-nixos (NixOS-WSL host)
#
# FOR PORTABLE WSL CONFIG (works on ANY WSL distro):
# See home/common/wsl-home-base.nix instead - that's a Home Manager module
# that works on any WSL distribution with Nix + home-manager installed.
#
# USAGE: Import this in NixOS-WSL host configs to get standard WSL system setup
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Dendritic system type - provides system-cli layer (includes default and minimal)
    inputs.self.modules.nixos.system-cli
    # WSL-specific modules
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
    ../../modules/nixos/sops-nix.nix
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-wsl.nixosModules.default
  ];

  # Allow unfree packages by default
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Minimal layer configuration (1-minimal)
  # NOTE: userName is intentionally NOT set here to require explicit configuration
  # When using this module, you MUST set systemDefault.userName in your host configuration
  systemMinimal = {
    nixMaxJobs = lib.mkDefault 8;
    nixCores = lib.mkDefault 0;
    enableBinaryCache = lib.mkDefault true;
    cacheTimeout = lib.mkDefault 10;
  };

  # Default layer configuration (2-default)
  systemDefault = {
    # userName must be explicitly set in host configuration (no default)
    userGroups = lib.mkDefault [ "wheel" "dialout" ];
    sshPasswordAuth = lib.mkDefault true;
    wheelNeedsPassword = lib.mkDefault false;
    extraShellAliases = lib.mkDefault {
      esp32c5 = "esp-idf-shell";
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };
  };

  # CLI layer configuration (3-cli)
  systemCli = {
    enableClaudeCodeEnterprise = lib.mkDefault false;
    enablePodman = lib.mkDefault true;
  };

  # Enable WSL common configuration
  wslCommon.enable = lib.mkDefault true;

  # WSL-specific configuration
  wsl = {
    enable = true;
    interop.register = lib.mkDefault true;
    usbip.enable = lib.mkDefault true;
    usbip.autoAttach = lib.mkDefault [ "3-1" "3-2" ];
    usbip.snippetIpAddress = lib.mkDefault "localhost";
  };

  # SOPS-NiX configuration for secrets management
  sopsNix = {
    enable = lib.mkDefault true;
    hostKeyPath = lib.mkDefault "/etc/sops/age.key";
  };

  # System state version (override in host if needed)
  system.stateVersion = lib.mkDefault "24.11";
}
