# Podman user tools for Home Manager
{ config, lib, pkgs, ... }:

with lib;

let 
  cfg = config.programs.podman-tools;
in
{
  options.programs.podman-tools = {
    enable = mkEnableOption "podman user tools";
    
    enableCompose = mkOption {
      type = types.bool;
      default = true;
      description = "Enable podman-compose";
    };
    
    enableDesktopFiles = mkOption {
      type = types.bool;
      default = true;
      description = "Enable desktop integration for podman-desktop";
    };
    
    aliases = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Shell aliases for podman commands";
    };
  };
  
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      podman-tui
    ] ++ optional cfg.enableCompose podman-compose;
    
    # Shell aliases for common operations
    programs.bash.shellAliases = cfg.aliases;
    programs.zsh.shellAliases = cfg.aliases;
    
    # XDG configuration for podman
    xdg.configFile."containers/registries.conf".text = ''
      [registries.search]
      registries = ['docker.io', 'quay.io']
      
      [registries.insecure]
      registries = []
      
      [registries.block]
      registries = []
    '';
  };
}