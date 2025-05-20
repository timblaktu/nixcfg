# Parameterized base module for NixOS systems
{ config, lib, pkgs, ... }:

# Import the lib for easier option definitions
with lib;

let 
  cfg = config.base;
in
{
  # Define the module options
  options.base = {
    # SSH Configuration options
    sshPasswordAuth = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable SSH password authentication";
    };
    
    sshRootLogin = mkOption {
      type = types.str;
      default = "no";
      description = "SSH root login policy";
    };
    
    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "SSH authorized keys";
    };
    
    # User configuration options
    userName = mkOption {
      type = types.str;
      default = "tim";
      description = "Primary user name";
    };
    
    userGroups = mkOption {
      type = types.listOf types.str;
      default = [ "wheel" "networkmanager" "audio" "video" ];
      description = "User groups";
    };
    
    userShell = mkOption {
      type = types.package;
      default = pkgs.zsh;
      description = "Default user shell";
    };
    
    userPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "User-specific packages";
    };
    
    # Time and locale options
    timeZone = mkOption {
      type = types.str;
      default = "America/Los_Angeles";
      description = "System time zone";
    };
    
    locale = mkOption {
      type = types.str;
      default = "en_US.UTF-8";
      description = "System locale";
    };
    
    # Console options
    consoleFont = mkOption {
      type = types.str;
      default = "Lat2-Terminus16";
      description = "Console font";
    };
    
    consoleKeyMap = mkOption {
      type = types.str;
      default = "us";
      description = "Console keymap";
    };
    
    consolePackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Console-related packages";
    };
    
    # System packages
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional system packages";
    };
    
    # Security options
    requireWheelPassword = mkOption {
      type = types.bool;
      default = true;
      description = "Whether sudo requires password for wheel group";
    };
    
    # Nix options
    gcDates = mkOption {
      type = types.str;
      default = "weekly";
      description = "Garbage collection frequency";
    };
    
    gcOptions = mkOption {
      type = types.str;
      default = "--delete-older-than 30d";
      description = "Garbage collection options";
    };
    
    # System options
    stateVersion = mkOption {
      type = types.str;
      default = "24.11";
      description = "NixOS state version";
    };
    
    # Shell aliases
    additionalShellAliases = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional shell aliases";
    };
  };

  # Actual configuration based on the options
  config = {
    # Time zone and internationalization
    time.timeZone = lib.mkDefault cfg.timeZone;
    i18n.defaultLocale = lib.mkDefault cfg.locale;

    # Console configuration
    console = {
      font = lib.mkDefault cfg.consoleFont;
      keyMap = lib.mkDefault cfg.consoleKeyMap;
      packages = lib.mkDefault cfg.consolePackages;
    };

    # Enable OpenSSH daemon with configurable parameters
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PermitRootLogin = lib.mkDefault cfg.sshRootLogin;
        PasswordAuthentication = lib.mkDefault cfg.sshPasswordAuth;
      };
    };

    # Configure sudo access
    security.sudo.wheelNeedsPassword = lib.mkDefault cfg.requireWheelPassword;

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
    ] ++ cfg.additionalPackages;

    # System-wide shell aliases
    environment.shellAliases = {
      ll = "ls -la";
      update = "sudo nixos-rebuild switch";
      upgrade = "sudo nixos-rebuild switch --upgrade";
    } // cfg.additionalShellAliases;

    # Default shell configuration
    programs.zsh.enable = true;
    users.defaultUserShell = cfg.userShell;

    # System-level nix settings
    nix = {
      settings = {
        auto-optimise-store = true;
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" cfg.userName ];
      };
      gc = {
        automatic = true;
        dates = cfg.gcDates;
        options = cfg.gcOptions;
      };
    };

    # Default user configuration
    users.users.${cfg.userName} = {
      isNormalUser = lib.mkDefault true;
      extraGroups = lib.mkDefault cfg.userGroups;
      shell = lib.mkDefault cfg.userShell;
      packages = lib.mkDefault cfg.userPackages;
      openssh.authorizedKeys.keys = lib.mkDefault cfg.sshKeys;
    };

    # Set NixOS compatibility version
    system.stateVersion = cfg.stateVersion;
  };
}
