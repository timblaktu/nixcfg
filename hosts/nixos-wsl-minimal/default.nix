# Minimal NixOS-WSL configuration for distribution
# This configuration creates a lightweight, shareable NixOS-WSL instance
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ../../modules/wsl-tarball-checks.nix
    inputs.nixos-wsl.nixosModules.default
  ];

  # Keep it free for distribution
  nixpkgs.config.allowUnfree = false;

  # WSL configuration
  wsl = {
    enable = true;
    defaultUser = "nixos"; # Generic default user

    # Enable basic Windows integration
    interop = {
      register = true;
      includePath = true;
    };

    # Standard WSL mount configuration
    wslConf = {
      automount.root = "/mnt";
      interop.appendWindowsPath = true;
    };

    # Disable advanced features by default (users can enable if needed)
    usbip.enable = false;
    # crossInstanceMount.enable = false;
  };

  # Hostname - generic name for distribution
  networking.hostName = "nixos-wsl";

  # User configuration - minimal setup
  users.users.nixos = {
    isNormalUser = true;
    description = "NixOS User";
    extraGroups = [ "wheel" ];
    shell = pkgs.bash; # Use bash by default for compatibility

    # Set a default password that users should change
    # Password is "nixos" - users should change this immediately
    initialPassword = "nixos";
  };

  # Enable sudo without password for wheel group initially
  # Users should configure this according to their security needs
  security.sudo.wheelNeedsPassword = false;

  # Essential system packages only
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    git
    wget
    curl
    htop
    tree

    # WSL utilities
    wslu

    # Nix tools
    nixpkgs-fmt
    nil # Nix language server
  ];

  # Basic shell aliases for Windows integration
  environment.shellAliases = {
    # Windows interop shortcuts
    explorer = "explorer.exe";
    notepad = "notepad.exe";

    # Nix shortcuts
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl-minimal";
    update = "nix flake update /etc/nixos";
  };

  # Enable nix flakes and modern nix command
  nix = {
    package = pkgs.nixVersions.stable;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];

      # Optimize storage automatically
      auto-optimise-store = true;

      # Trusted users for binary cache
      trusted-users = [ "root" "@wheel" ];
    };

    # Garbage collection settings
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Basic networking configuration
  networking = {
    # Enable basic networking
    networkmanager.enable = false; # Not needed in WSL

    # Firewall disabled by default in WSL
    firewall.enable = false;
  };

  # OpenSSH for remote access (disabled by default)
  services.openssh = {
    enable = false; # Users can enable if needed
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Locale settings
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York"; # Users should adjust

  # Console configuration
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Documentation
  documentation = {
    enable = true;
    man.enable = true;
    info.enable = true;
    doc.enable = true;
  };

  # This value determines the NixOS release with which your system is compatible
  system.stateVersion = "24.11";

  # Add helpful message on first login
  programs.bash.interactiveShellInit = ''
    if [ -f ~/.first-login ]; then
      echo "======================================"
      echo "Welcome to NixOS-WSL!"
      echo ""
      echo "Quick start:"
      echo "1. Change your password: passwd"
      echo "2. Edit configuration: sudo vim /etc/nixos/configuration.nix"
      echo "3. Rebuild system: sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl-minimal"
      echo ""
      echo "For more information:"
      echo "- NixOS Manual: https://nixos.org/manual/nixos/stable/"
      echo "- NixOS-WSL Docs: https://nix-community.github.io/NixOS-WSL/"
      echo "======================================"
      rm ~/.first-login
    fi
  '';

  # Create first-login flag for new users
  system.activationScripts.firstLogin = ''
    if [ ! -f /home/nixos/.first-login ]; then
      touch /home/nixos/.first-login
      chown nixos:users /home/nixos/.first-login
    fi
  '';
}
