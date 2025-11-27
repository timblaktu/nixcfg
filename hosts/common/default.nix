# Common configuration shared by all NixOS systems
{ config, lib, pkgs, ... }:

{
  # Set your time zone
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";

  # Configure console keymap
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
    tmux
    ripgrep
    fd
  ];

  # Default shell configuration
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # System-level nix settings
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "tim" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Default user configuration
  users.users.tim = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    openssh.authorizedKeys.keys = [ ];
    linger = true; # Enable systemd user session persistence
  };

  # System-wide aliases
  environment.shellAliases = {
    ll = "ls -la";
    update = "sudo nixos-rebuild switch";
    upgrade = "sudo nixos-rebuild switch --upgrade";
  };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
