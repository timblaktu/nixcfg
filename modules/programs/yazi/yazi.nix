# modules/programs/yazi/yazi.nix
# Yazi terminal file manager configuration [nd]
#
# Provides:
#   flake.modules.homeManager.yazi - Full yazi configuration
#
# Features:
#   - Custom compact_meta linemode (size, mtime, permissions in 20 chars)
#   - Patched glow plugin for dynamic preview width
#   - WSL2 clipboard integration (clip.exe keybindings)
#   - Plugin ecosystem (toggle-pane, mediainfo, miller, ouch, chmod, git, etc.)
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.yazi ];
{ config, lib, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.yazi = { config, pkgs, lib, ... }:
      {
        programs.yazi = {
          enable = true;
          enableZshIntegration = true;
          plugins = {
            inherit (pkgs.yaziPlugins) toggle-pane;
            inherit (pkgs.yaziPlugins) mediainfo;
            # Override glow plugin to use dynamic width instead of hardcoded 55
            glow = pkgs.yaziPlugins.glow.overrideAttrs (_old: {
              postPatch = ''
                # Replace main.lua with our patched version
                cp ${./files/yazi-glow-main.lua} main.lua
              '';
            });
            inherit (pkgs.yaziPlugins) miller;
            inherit (pkgs.yaziPlugins) ouch;
            # Additional useful plugins
            inherit (pkgs.yaziPlugins) chmod;
            inherit (pkgs.yaziPlugins) full-border;
            inherit (pkgs.yaziPlugins) git;
            inherit (pkgs.yaziPlugins) smart-enter;
          };
          initLua = ./files/yazi-init.lua;
          settings = {
            # Full settings spec at https://yazi-rs.github.io/docs/configuration/yazi
            log = {
              enabled = true;
            };
            mgr = {
              linemode = "compact_meta";
              ratio = [ 1 3 5 ];
              show_hidden = true;
              show_symlink = true;
              sort_by = "mtime"; # natural, size
              sort_dir_first = true;
              sort_reverse = true;
              sort_sensitive = true;
              mouse_events = [ "click" "scroll" "touch" "move" ];
            };
            preview = {
              tab_size = 2;
              max_width = 600;
              max_height = 900;
              cache_dir = "";
              image_delay = 30;
              image_filter = "triangle";
              image_quality = 75;
              wrap = "no";
            };
            plugin = {
              prepend_previewers = [
                {
                  name = "*.md";
                  run = "glow";
                }
              ];
            };
            opener = {
              edit = [
                {
                  run = ''$EDITOR "$1"'';
                  desc = "$EDITOR";
                  block = true;
                  for = "unix";
                }
              ];
              open = [
                {
                  run = ''explorer.exe "$1"'';
                  desc = "Open in Windows Explorer";
                  for = "unix";
                }
              ];
            };
          };
          keymap = {
            mgr.prepend_keymap = [
              # WSL2 clipboard integration - override default copy commands to use clip.exe
              {
                on = "cc";
                run = [ ''shell -- echo "$1" | clip.exe'' "copy path" ];
                desc = "Copy absolute path to Windows clipboard";
              }
              {
                on = "cd";
                run = [ ''shell -- echo "$1" | clip.exe'' "copy dirname" ];
                desc = "Copy directory path to Windows clipboard";
              }
              {
                on = "cf";
                run = [ ''shell -- echo "$1" | clip.exe'' "copy filename" ];
                desc = "Copy filename to Windows clipboard";
              }
              {
                on = "cn";
                run = [ ''shell -- echo "$1" | clip.exe'' "copy name_without_ext" ];
                desc = "Copy name without extension to Windows clipboard";
              }
              # Additional useful keybindings
              {
                on = "T";
                run = "plugin --sync toggle-pane";
                desc = "Toggle preview pane";
              }
              {
                on = "<C-s>";
                run = "plugin --sync smart-enter";
                desc = "Smart enter (enter dir or open file)";
              }
              {
                on = "cM";
                run = "plugin --sync chmod";
                desc = "Change file permissions";
              }
            ];
          };
        };

        # Enable yazi debug logging via environment variable
        home.sessionVariables = {
          YAZI_LOG = "debug";
        };
      };
  };
}
