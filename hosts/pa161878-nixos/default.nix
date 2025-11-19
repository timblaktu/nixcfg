# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ../../modules/base.nix
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
    ../../modules/nixos/sops-nix.nix
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-wsl.nixosModules.default
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Base module configuration
  base = {
    userName = "tim";
    userGroups = [ "wheel" "dialout" ];
    enableClaudeCodeEnterprise = false;
    nixMaxJobs = 8;
    nixCores = 0;
    enableBinaryCache = true;
    cacheTimeout = 10;
    sshPasswordAuth = true;
    requireWheelPassword = false;
    additionalShellAliases = {
      esp32c5 = "esp-idf-shell";
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };
  };

  # WSL common configuration
  wslCommon = {
    enable = true;
    hostname = "pa161878-nixos";
    defaultUser = "tim";
    sshPort = 2223; # Must bind to unique port since sharing winHost with another WSL guest
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com"
    ];
    enableWindowsTools = true;
  };

  # WSL-specific configuration
  wsl.enable = true;
  # wsl.defaultUser = "tim";
  wsl.interop.register = true;
  wsl.usbip.enable = true;
  wsl.usbip.autoAttach = [ "3-1" "3-2" ]; # .. the last on new sabrent hub is 8-4
  wsl.usbip.snippetIpAddress = "localhost"; # Fix for auto-attach

  # SSH service configuration
  services.openssh = {
    enable = true;
    ports = [ 2223 ]; # Must bind to unique port since sharing winHost with another WSL guest
  };

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@pa161878-nixos'

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

  # System state version
  system.stateVersion = "24.11";
}
