# Development packages and tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableDevelopment {
    # Development-specific packages
    home.packages = with pkgs; [
      cmake
      doxygen
      entr
      gcc
      gnumake
      binutils
      cacert
      nix-prefetch-github
      rust-analyzer
      rustc
      cargo
      rustfmt
      clippy
      nodejs
      yarn
      (python3.withPackages (ps: with ps; [
        ipython
        pip
        setuptools
        pyserial
        cryptography
        pyparsing
      ]))
      flex
      bison
      gperf
      psmisc
      libffi
      openssl
      ncurses

      podman
      podman-compose
      kubectl
      k9s

      fzf
      bat
      eza # Modern ls replacement (formerly exa)
      delta # better git diff
      bottom # system monitoring
      miller # Command-line CSV/TSV/JSON processor

      # Claude development workflow scripts
      (pkgs.writeShellApplication {
        name = "claudevloop";
        text = builtins.readFile ../files/bin/claudevloop;
        runtimeInputs = with pkgs; [ neovim ];
      })

      (pkgs.writeShellApplication {
        name = "restart_claude";
        text = builtins.readFile ../files/bin/restart_claude;
        runtimeInputs = with pkgs; [ jq findutils coreutils ];
      })

      (pkgs.writeShellApplication {
        name = "mkclaude_desktop_config";
        text = builtins.readFile ../files/bin/mkclaude_desktop_config;
        runtimeInputs = with pkgs; [ jq coreutils ];
      })

      # Claude Code account wrapper scripts
      (pkgs.writeShellApplication {
        name = "claudemax";
        text =
          let
            mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
              account="${account}"
              config_dir="${configDir}"
              pidfile="/tmp/claude-''${account}.pid"
            
              # Check for headless mode - bypass PID check for stateless operations
              if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
                export CLAUDE_CONFIG_DIR="$config_dir"
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
                exec "${pkgs.claude-code}/bin/claude" "$@"
              fi

              # Production Claude detection logic  
              if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
                exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
              fi

              # PID-based single instance management
              if [[ -f "$pidfile" ]]; then
                pid=$(cat "$pidfile")
                if kill -0 "$pid" 2>/dev/null; then
                  echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
                  echo "   Using existing instance..."
                  exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
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
              exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
            '';
          in
          mkClaudeWrapperScript {
            account = "max";
            displayName = "Claude Max Account";
            configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-max";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
        runtimeInputs = with pkgs; [ procps coreutils claude-code ];
      })

      (pkgs.writeShellApplication {
        name = "claudepro";
        text =
          let
            mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
              account="${account}"
              config_dir="${configDir}"
              pidfile="/tmp/claude-''${account}.pid"
            
              # Check for headless mode - bypass PID check for stateless operations
              if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
                export CLAUDE_CONFIG_DIR="$config_dir"
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
                exec "${pkgs.claude-code}/bin/claude" "$@"
              fi

              # Production Claude detection logic  
              if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
                exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
              fi

              # PID-based single instance management
              if [[ -f "$pidfile" ]]; then
                pid=$(cat "$pidfile")
                if kill -0 "$pid" 2>/dev/null; then
                  echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
                  echo "   Using existing instance..."
                  exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
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
              exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
            '';
          in
          mkClaudeWrapperScript {
            account = "pro";
            displayName = "Claude Pro Account";
            configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-pro";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
        runtimeInputs = with pkgs; [ procps coreutils claude-code ];
      })
    ];
  };
}
