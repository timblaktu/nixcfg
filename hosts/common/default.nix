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

  # Fix user runtime directory ownership for WSL
  # WSL creates /run/user/UID with root:root ownership instead of user:group
  # This prevents systemd --user from starting (pam_systemd ownership check fails)
  #
  # WORKAROUND: Manual fix required after WSL restart
  # Run: sudo chown -R tim:users /run/user/1000 && sudo systemctl start user@1000
  #
  # TODO: Investigate why tmpfiles.d/systemd service approaches don't work
  # Attempted solutions:
  # - systemd.tmpfiles.rules (not included in generated config)
  # - systemd.tmpfiles.settings (config file not created)
  # - system.activationScripts (script not executed)
  # - systemd.services (service unit not created)

  # System-wide aliases
  environment.shellAliases = {
    ll = "ls -la";
    update = "sudo nixos-rebuild switch";
    upgrade = "sudo nixos-rebuild switch --upgrade";
  };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
