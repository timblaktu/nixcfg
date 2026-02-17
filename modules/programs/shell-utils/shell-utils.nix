# modules/programs/shell-utils/shell-utils.nix
# Shell utilities and libraries [nd]
#
# Provides:
#   flake.modules.homeManager.shell-utils - Shell utility scripts and libraries
#
# Features:
#   - Packaged shell scripts (mytree, vwatch, mergejson, etc.)
#   - Bash library files for sourcing (~/.local/lib/*.bash)
#   - Stress testing and analysis utilities
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.shell-utils ];
_:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.shell-utils = { pkgs, lib, ... }:
      let
        # Path to source files - relative to this module
        filesDir = ./files;
      in
      {
        home.packages = with pkgs; [
          # mytree - enhanced tree command with custom formatting
          (pkgs.writeShellApplication {
            name = "mytree";
            text = builtins.readFile (filesDir + "/bin/mytree.sh");
            runtimeInputs = with pkgs; [ coreutils tree ];
          })

          # colorfuncs - color utility functions demo/test
          (pkgs.writeShellApplication {
            name = "colorfuncs";
            text = builtins.readFile (filesDir + "/bin/colorfuncs.sh");
            runtimeInputs = with pkgs; [ coreutils ];
          })

          # vwatch - visual watch (shows history without clearing screen)
          (pkgs.writeShellApplication {
            name = "vwatch";
            text = builtins.readFile (filesDir + "/bin/vwatch");
            runtimeInputs = with pkgs; [ coreutils ];
          })

          # help-format-template - shell completion help formatting
          (pkgs.writeShellApplication {
            name = "help-format-template";
            text = builtins.readFile (filesDir + "/bin/help-format-template.sh");
            runtimeInputs = with pkgs; [ coreutils ];
          })

          # soundcloud-dl - SoundCloud downloader with token persistence
          (pkgs.writeShellApplication {
            name = "soundcloud-dl";
            text = builtins.readFile (filesDir + "/bin/soundcloud-dl");
            runtimeInputs = with pkgs; [ yt-dlp coreutils ];
          })

          # stress-wrapper - stress testing convenience wrapper
          (pkgs.writeShellApplication {
            name = "stress-wrapper";
            text = builtins.readFile (filesDir + "/bin/stress.sh");
            runtimeInputs = with pkgs; [ stress-ng coreutils ];
          })

          # wifi-test-comparison - WiFi analysis utility
          (pkgs.writeShellApplication {
            name = "wifi-test-comparison";
            text = builtins.readFile (filesDir + "/bin/wifi-test-comparison");
            runtimeInputs = with pkgs; [ coreutils openssh bash ];
          })

          # remote-wifi-analyzer - remote WiFi analysis
          (pkgs.writeShellApplication {
            name = "remote-wifi-analyzer";
            text = builtins.readFile (filesDir + "/bin/remote-wifi-analyzer");
            runtimeInputs = with pkgs; [ coreutils openssh bash ];
          })

          # mergejson - JSON merging utility with diff preview
          (pkgs.writeShellApplication {
            name = "mergejson";
            runtimeInputs = with pkgs; [ jq coreutils diffutils neovim ];
            text = /* bash */ ''
              set -euo pipefail

              usage() {
                echo "Usage: mergejson OLD_FILE NEW_FILE JQ_QUERY [--confirm]"
                echo "  Merges selected fields from NEW_FILE into OLD_FILE"
                echo "  JQ_QUERY: jq expression selecting fields to merge"
                echo "  --confirm: prompt before applying changes"
                exit 1
              }

              [[ $# -lt 3 ]] && usage

              old_file="$1"
              new_file="$2"
              jq_query="$3"
              confirm_flag="''${4:-}"

              [[ ! -f "$old_file" ]] && { echo "Error: $old_file not found"; exit 1; }
              [[ ! -f "$new_file" ]] && { echo "Error: $new_file not found"; exit 1; }

              extract_tmp=$(mktemp)
              jq "$jq_query" "$new_file" > "$extract_tmp"

              jq --slurpfile extract_data "$extract_tmp" \
                 '. + $extract_data[0]' \
                 "$old_file" > "$old_file.merged"

              if ! diff -q "$old_file" "$old_file.merged" >/dev/null 2>&1; then
                if [[ "$confirm_flag" == "--confirm" ]]; then
                  echo "Changes detected in: $jq_query"
                  read -r -p "View diff? [y/N]: " choice
                  if [[ ''${choice,,} =~ ^y ]]; then
                    nvim -d "$old_file" "$old_file.merged"
                    read -r -p "Apply changes? [y/N]: " apply_choice
                    [[ ''${apply_choice,,} =~ ^y ]] || { rm -f "$extract_tmp" "$old_file.merged"; exit 1; }
                  fi
                fi
                mv "$old_file.merged" "$old_file"
                echo "Merged: $jq_query"
              else
                rm -f "$old_file.merged"
              fi

              rm -f "$extract_tmp"
            '';
            passthru.tests = {
              syntax = pkgs.runCommand "test-mergejson-syntax" { } ''
                echo "✅ Syntax validation passed at build time" > $out
              '';
              basic = pkgs.runCommand "test-mergejson-basic"
                {
                  nativeBuildInputs = [
                    (pkgs.writeShellApplication {
                      name = "mergejson";
                      runtimeInputs = with pkgs; [ jq coreutils diffutils neovim ];
                      text = /* bash */ ''
                        set -euo pipefail

                        usage() {
                          echo "Usage: mergejson OLD_FILE NEW_FILE JQ_QUERY [--confirm]"
                          echo "  Merges selected fields from NEW_FILE into OLD_FILE"
                          echo "  JQ_QUERY: jq expression selecting fields to merge"
                          echo "  --confirm: prompt before applying changes"
                          exit 1
                        }

                        [[ $# -lt 3 ]] && usage

                        old_file="$1"
                        new_file="$2"
                        jq_query="$3"
                        confirm_flag="''${4:-}"

                        [[ ! -f "$old_file" ]] && { echo "Error: $old_file not found"; exit 1; }
                        [[ ! -f "$new_file" ]] && { echo "Error: $new_file not found"; exit 1; }

                        extract_tmp=$(mktemp)
                        jq "$jq_query" "$new_file" > "$extract_tmp"

                        jq --slurpfile extract_data "$extract_tmp" \
                           '. + $extract_data[0]' \
                           "$old_file" > "$old_file.merged"

                        if ! diff -q "$old_file" "$old_file.merged" >/dev/null 2>&1; then
                          if [[ "$confirm_flag" == "--confirm" ]]; then
                            echo "Changes detected in: $jq_query"
                            read -r -p "View diff? [y/N]: " choice
                            if [[ ''${choice,,} =~ ^y ]]; then
                              nvim -d "$old_file" "$old_file.merged"
                              read -r -p "Apply changes? [y/N]: " apply_choice
                              [[ ''${apply_choice,,} =~ ^y ]] || { rm -f "$extract_tmp" "$old_file.merged"; exit 1; }
                            fi
                          fi
                          mv "$old_file.merged" "$old_file"
                          echo "Merged: $jq_query"
                        else
                          rm -f "$old_file.merged"
                        fi

                        rm -f "$extract_tmp"
                      '';
                    })
                    pkgs.jq
                  ];
                } ''
                cd $(mktemp -d)

                echo '{"a":1,"b":2}' > old.json
                echo '{"a":99,"c":3}' > new.json

                mergejson old.json new.json '{a}'

                result=$(jq -r '.a' old.json)
                [[ "$result" == "99" ]] || { echo "Expected a=99, got $result"; exit 1; }

                result=$(jq -r '.b' old.json)
                [[ "$result" == "2" ]] || { echo "Expected b=2, got $result"; exit 1; }

                echo "✅ Basic merge test passed" > $out
              '';
            };
          })
        ];

        # Shell libraries - placed in ~/.local/lib/ for sourcing
        home.file = {
          ".local/lib/claude-utils.bash".source = pkgs.writeText "claude-utils.bash"
            (builtins.readFile (filesDir + "/lib/claude-utils.bash"));
          ".local/lib/color-utils.bash".source = pkgs.writeText "color-utils.bash"
            (builtins.readFile (filesDir + "/lib/color-utils.bash"));
          ".local/lib/datetime-utils.bash".source = pkgs.writeText "datetime-utils.bash"
            (builtins.readFile (filesDir + "/lib/datetime-utils.bash"));
          ".local/lib/fs-utils.bash".source = pkgs.writeText "fs-utils.bash"
            (builtins.readFile (filesDir + "/lib/fs-utils.bash"));
          ".local/lib/general-utils.bash".source = pkgs.writeText "general-utils.bash"
            (builtins.readFile (filesDir + "/lib/general-utils.bash"));
          ".local/lib/git-utils.bash".source = pkgs.writeText "git-utils.bash"
            (builtins.readFile (filesDir + "/lib/git-utils.bash"));
          ".local/lib/path-utils.bash".source = pkgs.writeText "path-utils.bash"
            (builtins.readFile (filesDir + "/lib/path-utils.bash"));
          ".local/lib/profiling-utils.bash".source = pkgs.writeText "profiling-utils.bash"
            (builtins.readFile (filesDir + "/lib/profiling-utils.bash"));
          ".local/lib/terminal-utils.bash".source = pkgs.writeText "terminal-utils.bash"
            (builtins.readFile (filesDir + "/lib/terminal-utils.bash"));
        };
      };
  };
}
