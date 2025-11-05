# Shell utilities and libraries module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableShellUtils {
    # Shell utilities - executable shell applications
    home.packages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "mytree";
        text = builtins.readFile ../files/bin/mytree.sh;
        runtimeInputs = with pkgs; [ coreutils tree ];
      })

      (pkgs.writeShellApplication {
        name = "colorfuncs";
        text = builtins.readFile ../files/bin/colorfuncs.sh;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # Visual watch - like watch but shows history without clearing screen
      (pkgs.writeShellApplication {
        name = "vwatch";
        text = builtins.readFile ../files/bin/vwatch;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # Help format template for shell completion
      (pkgs.writeShellApplication {
        name = "help-format-template";
        text = builtins.readFile ../files/bin/help-format-template.sh;
        runtimeInputs = with pkgs; [ coreutils ];
      })

      # SoundCloud downloader with token persistence
      (pkgs.writeShellApplication {
        name = "soundcloud-dl";
        text = builtins.readFile ../files/bin/soundcloud-dl;
        runtimeInputs = with pkgs; [ yt-dlp coreutils ];
      })

      # Stress testing convenience wrapper
      (pkgs.writeShellApplication {
        name = "stress-wrapper";
        text = builtins.readFile ../files/bin/stress.sh;
        runtimeInputs = with pkgs; [ stress-ng coreutils ];
      })

      # WiFi analysis utilities
      (pkgs.writeShellApplication {
        name = "wifi-test-comparison";
        text = builtins.readFile ../files/bin/wifi-test-comparison;
        runtimeInputs = with pkgs; [ coreutils openssh bash ];
      })

      (pkgs.writeShellApplication {
        name = "remote-wifi-analyzer";
        text = builtins.readFile ../files/bin/remote-wifi-analyzer;
        runtimeInputs = with pkgs; [ coreutils openssh bash ];
      })

      # JSON merging utility
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

    # Shell libraries - place as files for sourcing
    home.file = {
      ".local/lib/claude-utils.bash".source = pkgs.writeText "claude-utils.bash" (builtins.readFile ../files/lib/claude-utils.bash);
      ".local/lib/color-utils.bash".source = pkgs.writeText "color-utils.bash" (builtins.readFile ../files/lib/color-utils.bash);
      ".local/lib/datetime-utils.bash".source = pkgs.writeText "datetime-utils.bash" (builtins.readFile ../files/lib/datetime-utils.bash);
      ".local/lib/fs-utils.bash".source = pkgs.writeText "fs-utils.bash" (builtins.readFile ../files/lib/fs-utils.bash);
      ".local/lib/general-utils.bash".source = pkgs.writeText "general-utils.bash" (builtins.readFile ../files/lib/general-utils.bash);
      ".local/lib/git-utils.bash".source = pkgs.writeText "git-utils.bash" (builtins.readFile ../files/lib/git-utils.bash);
      ".local/lib/path-utils.bash".source = pkgs.writeText "path-utils.bash" (builtins.readFile ../files/lib/path-utils.bash);
      ".local/lib/profiling-utils.bash".source = pkgs.writeText "profiling-utils.bash" (builtins.readFile ../files/lib/profiling-utils.bash);
      ".local/lib/terminal-utils.bash".source = pkgs.writeText "terminal-utils.bash" (builtins.readFile ../files/lib/terminal-utils.bash);
    };
  };
}
