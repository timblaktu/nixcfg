# Parameterized Home Manager base module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in {
  imports = [
    # Always import these common modules
    ../common/git.nix
    ../common/tmux.nix
    ../common/neovim.nix
  ];
  
  options.homeBase = {
    # User information
    username = mkOption {
      type = types.str;
      default = "tim";
      description = "Username for Home Manager";
    };
    
    homeDirectory = mkOption {
      type = types.str;
      default = "/home/tim";
      description = "Home directory path";
    };
    
    # Basic packages common to all environments
    basePackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        ripgrep
        fd
        jq
        htop
        curl
        wget
        unzip
        tree
      ];
      description = "Base packages for all environments";
    };
    
    # Additional packages specific to this configuration
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages for this specific configuration";
    };
    
    # Shell configuration
    shellAliases = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Shell aliases";
    };
    
    # Editor preferences
    defaultEditor = mkOption {
      type = types.str;
      default = "nvim";
      description = "Default editor";
    };
    
    # Enable standard modules
    enableGit = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Git configuration";
    };
    
    enableTmux = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tmux configuration";
    };
    
    enableNeovim = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Neovim configuration";
    };
    
    # Environment variables
    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables";
    };
    
    # State version
    stateVersion = mkOption {
      type = types.str;
      default = "24.11";
      description = "Home Manager state version";
    };
  };

  # Conditionally import common modules based on configuration
  config = mkMerge [
    # Always apply these configs
    {
      # Home Manager needs information about you and the paths it should manage
      home = {
        username = cfg.username;
        homeDirectory = cfg.homeDirectory;
        
        # Packages combined from base and additional sets
        packages = cfg.basePackages ++ cfg.additionalPackages;
        
        # State version for Home Manager
        stateVersion = cfg.stateVersion;
        
        # Set environment variables
        sessionVariables = {
          EDITOR = cfg.defaultEditor;
        } // cfg.environmentVariables;
      };

      # Configure shell aliases
      programs.bash.shellAliases = lib.mkDefault cfg.shellAliases;
      programs.zsh.shellAliases = lib.mkDefault cfg.shellAliases;

      # Let Home Manager install and manage itself
      programs.home-manager.enable = true;

      # Enable/disable modules based on configuration
      programs.git.enable = cfg.enableGit;
      programs.tmux.enable = cfg.enableTmux;
      programs.neovim.enable = cfg.enableNeovim;
    }
  ];
}
