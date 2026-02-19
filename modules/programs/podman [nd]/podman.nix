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
#   - Platform-aware shell aliases:
#       Linux:  docker → podman (podman is the system container engine)
#       Darwin: no docker alias (Docker Desktop provides docker)
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.podman ];
#   programs.podman-tools.enable = true;
#   # Aliases are platform-aware by default; override if needed:
#   # programs.podman-tools.aliases = { docker = "podman"; };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Podman Tools Module ===
    homeManager.podman = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.programs.podman-tools;

        # Platform-aware default aliases:
        # - Linux: podman is the system container engine, so alias docker→podman
        #   for compatibility with scripts/docs that reference docker.
        # - Darwin: Docker Desktop provides the 'docker' command and daemon
        #   (via a hidden Linux VM). Aliasing docker→podman would break it
        #   since podman has no daemon on macOS without Podman Desktop.
        defaultAliases = if pkgs.stdenv.isDarwin then {
          # No docker→podman alias on Darwin (Docker Desktop is the engine)
        } else {
          docker = "podman";
          d = "podman";
          dc = "podman-compose";
        };
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
            default = defaultAliases;
            description = ''
              Shell aliases for podman commands.
              On Linux, defaults to docker=podman, d=podman, dc=podman-compose.
              On Darwin, defaults to empty (Docker Desktop provides docker).
            '';
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
