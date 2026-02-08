# modules/system/settings/wsl-home/wsl-home.nix
# WSL Home Manager configuration [nd]
#
# Provides:
#   flake.modules.homeManager.wsl-home - WSL user-level configuration
#
# PLATFORM REQUIREMENTS: ANY WSL distribution + Nix + home-manager ✅
# This is a Home Manager module that works on ANY WSL distribution
# where Nix and home-manager are installed (NixOS-WSL, Ubuntu, Debian, Alpine, etc.)
#
# For NixOS-WSL system-level config, see:
#   modules/system/settings/wsl/ - NixOS system module (requires NixOS-WSL)
#
# Features:
#   - User-level WSL tweaks (shell aliases, environment variables)
#   - Windows Terminal settings management (via targets.wsl)
#   - WSL utilities (wslu package)
#   - Windows interop tools (explorer.exe, code.exe aliases)
#
# Usage in host home config:
#   imports = [
#     inputs.self.modules.homeManager.wsl-home
#   ];
#   wsl-home-settings = {
#     enableWindowsAliases = true;
#     distroName = "nixos";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager WSL Module ===
    homeManager.wsl-home = { config, lib, pkgs, ... }:
      let
        cfg = config.wsl-home-settings;
      in
      {
        options.wsl-home-settings = {
          # === Core Settings ===
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable WSL home-manager configuration";
          };

          distroName = lib.mkOption {
            type = lib.types.str;
            default = "nixos";
            description = "WSL distribution name for environment variables";
            example = "Ubuntu";
          };

          editor = lib.mkOption {
            type = lib.types.str;
            default = "nvim";
            description = "Default editor";
          };

          # === Feature Toggles ===
          # NOTE: These options were removed in Task 6.4.9.
          # Features are now enabled by importing dendritic modules directly:
          #   - development-tools module (with developmentTools.enable)
          #   - esp-idf module (with espIdf.enable)
          #   - onedrive module (with oneDriveUtils.enable)
          #   - shell-utils module (always enabled when imported)
          #   - terminal module (always enabled when imported)
          # See host files for import patterns.

          # === Windows Interop ===
          enableWindowsAliases = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Windows tool aliases (explorer, code, etc.)";
          };

          extraShellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
            example = {
              pwsh = "powershell.exe";
            };
          };

          # === Environment Variables ===
          extraEnvironmentVariables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional environment variables";
          };

          # === Windows Terminal ===
          windowsTerminal = {
            enablePowerShell = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable PowerShell integration in Windows Terminal";
            };

            enableCmd = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable cmd.exe integration in Windows Terminal";
            };

            enableWslPath = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable wslpath integration";
            };

            wslPathPath = lib.mkOption {
              type = lib.types.str;
              default = "/bin/wslpath";
              description = "Path to wslpath binary";
            };
          };
        };

        config = lib.mkIf cfg.enable (lib.mkMerge [
          # === Environment and Aliases ===
          {
            home.sessionVariables = {
              WSL_DISTRO = lib.mkDefault cfg.distroName;
              EDITOR = lib.mkDefault cfg.editor;
            } // cfg.extraEnvironmentVariables;

            programs.bash.shellAliases = lib.mkMerge [
              # Windows aliases
              (lib.mkIf cfg.enableWindowsAliases {
                explorer = lib.mkDefault "explorer.exe .";
                code = lib.mkDefault "code.exe";
                code-insiders = lib.mkDefault "code-insiders.exe";
                esp32c5 = lib.mkDefault "esp-idf-shell";
              })
              cfg.extraShellAliases
            ];

            programs.zsh.shellAliases = lib.mkMerge [
              # Windows aliases
              (lib.mkIf cfg.enableWindowsAliases {
                explorer = lib.mkDefault "explorer.exe .";
                code = lib.mkDefault "code.exe";
                code-insiders = lib.mkDefault "code-insiders.exe";
                esp32c5 = lib.mkDefault "esp-idf-shell";
              })
              cfg.extraShellAliases
            ];
          }

          # === WSL Utilities ===
          {
            home.packages = with pkgs; [
              wslu # WSL utilities (wslview, wslfetch, wslvar, etc.)
            ];
          }

          # === Windows Terminal Target Configuration ===
          {
            targets.wsl = {
              enable = true;
              windowsTools = {
                enablePowerShell = lib.mkDefault cfg.windowsTerminal.enablePowerShell;
                enableCmd = lib.mkDefault cfg.windowsTerminal.enableCmd;
                enableWslPath = lib.mkDefault cfg.windowsTerminal.enableWslPath;
                wslPathPath = lib.mkDefault cfg.windowsTerminal.wslPathPath;
              };
            };
          }
        ]);
      };
  };
}
