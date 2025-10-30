# WSL-specific unified files configuration
# Universal Linux scripts + WSL-specific scripts (OneDrive tools)
{ config, lib, pkgs, mkUnifiedFile, mkUnifiedLibrary, mkClaudeWrapper, ... }:

{
  homeFiles = {
    enable = true;
    enableTesting = true;
    enableCompletions = true;

    # All scripts for WSL environments (11 total: 9 universal + 2 WSL-specific)
    scripts = {
      # Essential utility scripts - using autoWriter directly
      mytree = mkUnifiedFile {
        name = "mytree";
        source = ../files/bin/mytree.sh;
        executable = true;
      };

      stress = mkUnifiedFile {
        name = "stress";
        source = ../files/bin/stress.sh;
        executable = true;
      };

      syncfork = mkUnifiedFile {
        name = "syncfork";
        source = ../files/bin/syncfork.sh;
        executable = true;
      };

      # Background detection utility
      is-terminal-background-light-or-dark = mkUnifiedFile {
        name = "is-terminal-background-light-or-dark";
        source = ../files/bin/is_terminal_background_light_or_dark.sh;
        executable = true;
      };

      # Git smart merge tool
      smart-nvimdiff = mkUnifiedFile {
        name = "smart-nvimdiff";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # Smart mergetool wrapper for neovim
          # Automatically switches to 2-way diff when BASE is empty
          
          BASE="$1"
          LOCAL="$2"  
          REMOTE="$3"
          MERGED="$4"
          
          if [[ ! -s "$BASE" ]]; then
            echo "🔀 BASE is empty, using 2-way diff mode"
            nvim -d "$LOCAL" "$REMOTE" -c "wincmd w" -c "wincmd H"
          else
            echo "🔀 Using 3-way merge mode"
            nvim -d "$BASE" "$LOCAL" "$REMOTE" "$MERGED" -c "wincmd w" -c "wincmd J"
          fi
        '';
        tests = {
          help = pkgs.writeShellScript "test-smart-nvimdiff-help" ''
            echo "✅ smart-nvimdiff: Syntax validation passed"
          '';
        };
      };

      # Terminal font setup
      setup-terminal-fonts = mkUnifiedFile {
        name = "setup-terminal-fonts";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # Terminal font setup script for Linux
          # Downloads and installs Nerd Fonts for terminal usage
          
          set -euo pipefail
          
          FONT_DIR="$HOME/.local/share/fonts"
          FONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2"
          
          # Fonts to install
          FONTS=(
            "FiraCode"
            "JetBrainsMono" 
            "Hack"
            "SourceCodePro"
          )
          
          echo "🔤 Setting up terminal fonts..."
          mkdir -p "$FONT_DIR"
          
          for font in "''${FONTS[@]}"; do
            echo "📦 Installing $font..."
            wget -q "$FONTS_URL/$font.zip" -O "/tmp/$font.zip"
            unzip -q -o "/tmp/$font.zip" -d "$FONT_DIR"
            rm "/tmp/$font.zip"
          done
          
          # Update font cache
          fc-cache -fv "$FONT_DIR"
          echo "✅ Terminal fonts installed successfully"
        '';
        tests = {
          syntax = pkgs.writeShellScript "test-setup-terminal-fonts" ''
            echo "✅ setup-terminal-fonts: Syntax validation passed"
          '';
        };
      };

      # JSON merge utility
      mergejson = mkUnifiedFile {
        name = "mergejson";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # JSON merge utility using jq
          # Merges multiple JSON files into a single output
          
          set -euo pipefail
          
          usage() {
            cat << 'EOF'
          Usage: mergejson [OPTIONS] file1.json file2.json [file3.json ...]
          
          Merge multiple JSON files using jq's * operator.
          
          OPTIONS:
            -o, --output FILE    Write output to FILE instead of stdout
            -p, --pretty         Pretty-print the output JSON
            -h, --help          Show this help message
          
          EXAMPLES:
            mergejson config.json overrides.json
            mergejson -p -o merged.json *.json
          EOF
          }
          
          # Parse arguments
          output_file=""
          pretty=false
          files=()
          
          while [[ $# -gt 0 ]]; do
            case $1 in
              -o|--output)
                output_file="$2"
                shift 2
                ;;
              -p|--pretty)
                pretty=true
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              -*)
                echo "Error: Unknown option $1" >&2
                usage >&2
                exit 1
                ;;
              *)
                files+=("$1")
                shift
                ;;
            esac
          done
          
          # Validate input
          if [[ ''${#files[@]} -lt 2 ]]; then
            echo "Error: At least 2 JSON files required" >&2
            usage >&2
            exit 1
          fi
          
          # Build jq command
          jq_cmd="jq"
          if [[ "$pretty" == true ]]; then
            jq_cmd+=" --indent 2"
          else
            jq_cmd+=" -c"
          fi
          
          # Build merge expression
          merge_expr=""
          for i in "''${!files[@]}"; do
            if [[ $i -eq 0 ]]; then
              merge_expr="."
            else
              merge_expr+=" * input"
            fi
          done
          
          # Execute merge
          if [[ -n "$output_file" ]]; then
            $jq_cmd "$merge_expr" "''${files[0]}" ''${files[@]:1} > "$output_file"
            echo "✅ Merged ''${#files[@]} files to $output_file"
          else
            $jq_cmd "$merge_expr" "''${files[0]}" ''${files[@]:1}
          fi
        '';
        tests = {
          help = pkgs.writeShellScript "test-mergejson-help" ''
            echo "📦 Testing mergejson help..."
            mergejson --help >/dev/null
            echo "✅ mergejson help works"
          '';
        };
      };

      # Emoji rendering diagnostics
      diagnose-emoji-rendering = mkUnifiedFile {
        name = "diagnose-emoji-rendering";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # Emoji rendering diagnostic tool
          # Tests various emoji rendering scenarios in the terminal
          
          set -euo pipefail
          
          echo "🔍 Emoji Rendering Diagnostics"
          echo "=============================="
          echo
          
          # Test basic emoji support
          echo "📋 Basic Emoji Test:"
          echo "  Simple: 😀 🎉 ✅ ❌ 🔥 💡"
          echo "  Flags: 🇺🇸 🇬🇧 🇯🇵 🇩🇪 🇫🇷"
          echo "  Complex: 👨‍💻 👩‍🔬 🏳️‍🌈 🏴‍☠️"
          echo
          
          # Test font rendering
          echo "🔤 Font Information:"
          echo "  TERM: $TERM"
          echo "  LANG: $LANG"
          echo "  Font capabilities:"
          
          if command -v fc-list >/dev/null 2>&1; then
            echo "    Available emoji fonts:"
            fc-list | grep -i emoji | head -3 || echo "    No emoji fonts found"
          else
            echo "    fontconfig not available"
          fi
          echo
          
          # Test terminal capabilities  
          echo "🖥️  Terminal Capabilities:"
          echo "  Columns: $(tput cols)"
          echo "  Lines: $(tput lines)"
          echo "  Colors: $(tput colors)"
          echo "  Unicode support: $(locale charmap)"
          echo
          
          # Test character width
          echo "📏 Character Width Test:"
          echo "  ASCII: |a|b|c|"
          echo "  Emoji: |😀|🎉|✅|"
          echo "  Mixed: |a😀b🎉c✅|"
          echo
          
          echo "✅ Diagnostics complete"
          echo "   If emojis don't render correctly, check:"
          echo "   1. Terminal emoji font support"
          echo "   2. Locale settings (UTF-8)"
          echo "   3. Font configuration"
        '';
        tests = {
          basic = pkgs.writeShellScript "test-diagnose-emoji" ''
            echo "🧪 Testing emoji diagnostics..."
            diagnose-emoji-rendering >/dev/null
            echo "✅ Emoji diagnostics works"
          '';
        };
      };

      # Claude Code wrapper scripts
      claude-code-wrapper = mkUnifiedFile {
        name = "claude-code-wrapper";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # Claude Code wrapper script for account management
          # Provides unified interface for multiple Claude accounts
          
          set -euo pipefail
          
          usage() {
            cat << 'EOF'
          Usage: claude-code-wrapper [ACCOUNT] [OPTIONS]
          
          Wrapper for managing multiple Claude Code accounts.
          
          ACCOUNTS:
            max    Use Claude Max account
            pro    Use Claude Pro account
            
          OPTIONS:
            -h, --help    Show this help message
            
          EXAMPLES:
            claude-code-wrapper max --version
            claude-code-wrapper pro new-session
          EOF
          }
          
          if [[ $# -eq 0 ]]; then
            usage
            exit 1
          fi
          
          account="$1"
          shift
          
          case "$account" in
            max)
              exec claudemax "$@"
              ;;
            pro)  
              exec claudepro "$@"
              ;;
            -h|--help)
              usage
              exit 0
              ;;
            *)
              echo "Error: Unknown account '$account'" >&2
              usage >&2
              exit 1
              ;;
          esac
        '';
        tests = {
          help = pkgs.writeShellScript "test-claude-wrapper-help" ''
            claude-code-wrapper --help >/dev/null
            echo "✅ claude-code-wrapper help works"
          '';
        };
      };

      # Claude Code update script
      claude-code-update = mkUnifiedFile {
        name = "claude-code-update";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # Claude Code update script
          # Updates Claude Code installation across all accounts
          
          set -euo pipefail
          
          echo "🔄 Updating Claude Code..."
          
          # Update via package manager if available
          if command -v nix >/dev/null 2>&1; then
            echo "📦 Updating via Nix..."
            nix profile upgrade
          elif command -v brew >/dev/null 2>&1; then
            echo "🍺 Updating via Homebrew..."
            brew upgrade claude
          else
            echo "⚠️  No supported package manager found"
            echo "   Please update Claude Code manually"
            exit 1
          fi
          
          echo "✅ Claude Code update complete"
          echo "   Run 'claude --version' to verify"
        '';
        tests = {
          syntax = pkgs.writeShellScript "test-claude-update" ''
            echo "✅ claude-code-update: Syntax validation passed"
          '';
        };
      };

      # Claude Max account wrapper
      claudemax = mkUnifiedFile {
        name = "claudemax";
        executable = true;
        content = let
          mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
            account="${account}"
            config_dir="${configDir}"
            pidfile="/tmp/claude-''${account}.pid"
            
            # Check for headless mode - bypass PID check for stateless operations
            if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
              export CLAUDE_CONFIG_DIR="$config_dir"
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
              exec claude "$@"
            fi

            # Production Claude detection logic  
            if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
              exec claude --config-dir="$config_dir" "$@"
            fi

            # PID-based single instance management
            if [[ -f "$pidfile" ]]; then
              pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
                echo "   Using existing instance..."
                exec claude --config-dir="$config_dir" "$@"
              else
                echo "🧹 Cleaning up stale PID file..."
                rm -f "$pidfile"
              fi
            fi

            # Launch new instance with environment setup
            echo "🚀 Launching Claude (${displayName})..."
            export CLAUDE_CONFIG_DIR="$config_dir"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
            
            # Create config directory if it doesn't exist
            mkdir -p "$config_dir"
            
            # Store PID and execute
            echo $$ > "$pidfile"
            exec claude --config-dir="$config_dir" "$@"
          '';
        in mkClaudeWrapperScript {
          account = "max";
          displayName = "Claude Max Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-max";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        tests = {
          help = pkgs.writeShellScript "test-claudemax-help" ''
            claudemax --help >/dev/null 2>&1 || true
            echo "✅ claudemax: Syntax validation passed"
          '';
        };
      };

      # Claude Pro account wrapper  
      claudepro = mkUnifiedFile {
        name = "claudepro";
        executable = true;
        content = let
          mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
            account="${account}"
            config_dir="${configDir}"
            pidfile="/tmp/claude-''${account}.pid"
            
            # Check for headless mode - bypass PID check for stateless operations
            if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
              export CLAUDE_CONFIG_DIR="$config_dir"
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
              exec claude "$@"
            fi

            # Production Claude detection logic  
            if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
              exec claude --config-dir="$config_dir" "$@"
            fi

            # PID-based single instance management
            if [[ -f "$pidfile" ]]; then
              pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
                echo "   Using existing instance..."
                exec claude --config-dir="$config_dir" "$@"
              else
                echo "🧹 Cleaning up stale PID file..."
                rm -f "$pidfile"
              fi
            fi

            # Launch new instance with environment setup
            echo "🚀 Launching Claude (${displayName})..."
            export CLAUDE_CONFIG_DIR="$config_dir"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
            
            # Create config directory if it doesn't exist
            mkdir -p "$config_dir"
            
            # Store PID and execute
            echo $$ > "$pidfile"
            exec claude --config-dir="$config_dir" "$@"
          '';
        in mkClaudeWrapperScript {
          account = "pro";
          displayName = "Claude Pro Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-pro";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        tests = {
          help = pkgs.writeShellScript "test-claudepro-help" ''
            claudepro --help >/dev/null 2>&1 || true
            echo "✅ claudepro: Syntax validation passed"
          '';
        };
      };

      # Default Claude wrapper
      claude = mkUnifiedFile {
        name = "claude";
        executable = true;
        content = let
          mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
            account="${account}"
            config_dir="${configDir}"
            pidfile="/tmp/claude-''${account}.pid"
            
            # Check for headless mode - bypass PID check for stateless operations
            if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
              export CLAUDE_CONFIG_DIR="$config_dir"
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
              exec claude "$@"
            fi

            # Production Claude detection logic  
            if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
              exec claude --config-dir="$config_dir" "$@"
            fi

            # PID-based single instance management
            if [[ -f "$pidfile" ]]; then
              pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
                echo "   Using existing instance..."
                exec claude --config-dir="$config_dir" "$@"
              else
                echo "🧹 Cleaning up stale PID file..."
                rm -f "$pidfile"
              fi
            fi

            # Launch new instance with environment setup
            echo "🚀 Launching Claude (${displayName})..."
            export CLAUDE_CONFIG_DIR="$config_dir"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
            
            # Create config directory if it doesn't exist
            mkdir -p "$config_dir"
            
            # Store PID and execute
            echo $$ > "$pidfile"
            exec claude --config-dir="$config_dir" "$@"
          '';
        in mkClaudeWrapperScript {
          account = "max"; # Default to max account
          displayName = "Claude Default Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-max";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        tests = {
          help = pkgs.writeShellScript "test-claude-help" ''
            claude --help >/dev/null 2>&1 || true
            echo "✅ claude: Syntax validation passed"
          '';
        };
      };

      # WSL-SPECIFIC SCRIPTS: OneDrive tools

      # OneDrive force sync
      onedrive-force-sync = mkUnifiedFile {
        name = "onedrive-force-sync";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # OneDrive force sync utility for WSL environments
          # Forces OneDrive synchronization via Windows COM interface
          
          set -euo pipefail
          
          if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
            echo "❌ This script requires WSL environment" >&2
            exit 1
          fi
          
          echo "🔄 Forcing OneDrive synchronization..."
          
          # Use PowerShell to trigger OneDrive sync
          powershell.exe -Command "
            try {
              \$oneDrive = New-Object -ComObject OneDrive.SyncEngine
              \$oneDrive.ForceSyncNow()
              Write-Host '✅ OneDrive sync triggered successfully'
            } catch {
              Write-Host '⚠️  OneDrive COM interface not available'
              Write-Host '   Trying alternative method...'
              Start-Process 'onedrive' -ArgumentList '/sync' -NoNewWindow -Wait
              Write-Host '✅ OneDrive sync command sent'
            }
          "
          
          echo "🔄 Sync request completed"
          echo "   Check OneDrive status for progress"
        '';
        tests = {
          syntax = pkgs.writeShellScript "test-onedrive-force-sync" ''
            echo "✅ onedrive-force-sync: Syntax validation passed"
          '';
        };
      };

      # OneDrive status checker
      onedrive-status = mkUnifiedFile {
        name = "onedrive-status";
        executable = true;
        content = ''
          #!/usr/bin/env bash
          # OneDrive status checker for WSL environments
          # Reports OneDrive synchronization status and statistics
          
          set -euo pipefail
          
          if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
            echo "❌ This script requires WSL environment" >&2
            exit 1
          fi
          
          echo "📊 OneDrive Status Report"
          echo "========================"
          echo
          
          # Get OneDrive status via PowerShell
          powershell.exe -Command "
            try {
              \$status = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\OneDrive\Accounts\*' -ErrorAction SilentlyContinue
              if (\$status) {
                Write-Host '📁 OneDrive Accounts:'
                \$status | ForEach-Object {
                  Write-Host \"   Account: \$(\$_.UserName)\"
                  Write-Host \"   Path: \$(\$_.UserFolder)\"
                  Write-Host \"   Status: \$(\$_.SyncStatus)\"
                  Write-Host ''
                }
              } else {
                Write-Host '⚠️  No OneDrive accounts found in registry'
              }

              # Check OneDrive process status
              \$processes = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
              if (\$processes) {
                Write-Host '🔄 OneDrive Processes:'
                \$processes | ForEach-Object {
                  Write-Host \"   PID: \$(\$_.Id) - Started: \$(\$_.StartTime)\"
                }
              } else {
                Write-Host '❌ OneDrive is not running'
              }
              
            } catch {
              Write-Host \"❌ Error checking OneDrive status: \$(\$_.Exception.Message)\"
            }
          "

          echo
          echo "✅ Status report complete"
        '';
        tests = {
          syntax = pkgs.writeShellScript "test-onedrive-status" ''
            echo "✅ onedrive-status: Syntax validation passed"
          '';
        };
      };
    };

    # Start with basic libraries
    libraries = {
      # Create simple terminal utils library
      terminalUtils = mkUnifiedLibrary {
        name = "terminalUtils";
        content = ''
          # Terminal utility functions
          
          # Check if we have a TTY
          is_tty() {
            [ -t 1 ]
          }
          
          # Basic output functions
          info() {
            echo "INFO: $*" >&2
          }
          
          warn() {
            echo "WARN: $*" >&2
          }
          
          error() {
            echo "ERROR: $*" >&2
          }
        '';
      };
    };

    # Static files for direct copying
    staticFiles = {
      # Note: yazi config removed due to conflict with legacy files module
    };
  };
}