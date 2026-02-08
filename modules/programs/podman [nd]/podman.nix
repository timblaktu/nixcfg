# modules/programs/podman [nd]/podman.nix
# Podman user tools for home-manager
#
# Provides:
#   flake.modules.homeManager.podman - Container tools (podman-tui, podman-compose)
#
# Features:
#   - podman-tui for container management
#   - podman-compose for multi-container workflows
#   - Container registry configuration
#   - Shell aliases (docker → podman)
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.podman ];
#   programs.podman-tools = {
#     enable = true;
#     aliases.docker = "podman";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Podman Tools Module ===
    homeManager.podman = { config, lib, pkgs, ... }:
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
            default = { };
            description = "Shell aliases for podman commands";
            example = {
              docker = "podman";
              d = "podman";
              dc = "podman-compose";
            };
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
      };
  };
}
