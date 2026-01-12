# home/modules/claude-code/lib.nix
# Shared library functions for Claude Code wrapper generation
#
# Usage in development.nix or platform files:
#   let
#     claudeLib = import ./claude-code/lib.nix { inherit lib pkgs config; };
#   in
#     claudeLib.mkClaudeWrapperScript { ... }

{ lib, pkgs, config }:

{
  # Generate a Claude Code wrapper script for an account
  # Handles API proxy configuration, authentication, environment setup,
  # and V2.0 coalescence for Nix-managed config merging
  mkClaudeWrapperScript = {
    # Required parameters
    account,           # Account name (e.g., "max", "pro", "work")
    displayName,       # Human-readable name for messages
    configDir,         # Path to account config directory
    claudeBin ? "${pkgs.claude-code}/bin/claude",  # Path to claude binary

    # Optional API configuration (from account.api options)
    api ? {},

    # Optional secrets configuration (from account.secrets options)
    secrets ? {},

    # Optional extra environment variables (from account.extraEnvVars)
    extraEnvVars ? {}
  }:
  let
    # Extract API options with defaults
    baseUrl = api.baseUrl or null;
    authMethod = api.authMethod or "api-key";
    disableApiKey = api.disableApiKey or false;
    modelMappings = api.modelMappings or {};

    # Extract secrets options
    bearerToken = secrets.bearerToken or null;

    # Generate API environment variable exports
    apiEnvVars = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
      # ANTHROPIC_BASE_URL - set if custom baseUrl specified
      (lib.optionalString (baseUrl != null) ''
      export ANTHROPIC_BASE_URL="${baseUrl}"'')

      # ANTHROPIC_API_KEY - set to empty string if disableApiKey is true
      (lib.optionalString disableApiKey ''
      export ANTHROPIC_API_KEY=""'')

      # ANTHROPIC_AUTH_TOKEN - retrieve via rbw if bearer auth + bitwarden configured
      (lib.optionalString (authMethod == "bearer" && bearerToken != null && bearerToken.bitwarden or null != null) ''
      # Retrieve bearer token from Bitwarden via rbw
      if command -v rbw >/dev/null 2>&1; then
        ANTHROPIC_AUTH_TOKEN="$(rbw get "${bearerToken.bitwarden.item}" "${bearerToken.bitwarden.field}" 2>/dev/null)" || {
          echo "Warning: Failed to retrieve bearer token from Bitwarden" >&2
          echo "   Item: ${bearerToken.bitwarden.item}, Field: ${bearerToken.bitwarden.field}" >&2
        }
        export ANTHROPIC_AUTH_TOKEN
      else
        # Fallback for systems without rbw (e.g., Termux)
        if [[ -f "$HOME/.secrets/claude-${account}-token" ]]; then
          export ANTHROPIC_AUTH_TOKEN="$(cat "$HOME/.secrets/claude-${account}-token")"
        else
          echo "Warning: Bearer token not found" >&2
          echo "   Expected: ~/.secrets/claude-${account}-token (or rbw configured)" >&2
        fi
      fi'')
    ]);

    # Generate model mapping environment variables
    # Maps: sonnet -> ANTHROPIC_DEFAULT_SONNET_MODEL, etc.
    modelEnvVars = lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
      export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"'') modelMappings);

    # Generate extra environment variable exports
    extraEnvExports = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
      export ${k}="${v}"'') extraEnvVars);

    # Combined environment setup block
    envSetupBlock = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
      apiEnvVars
      modelEnvVars
      extraEnvExports
    ]);

  in ''
    account="${account}"
    config_dir="${configDir}"
    settings_file="$config_dir/settings.json"
    pidfile="/tmp/claude-''${account}.pid"

    # V2.0 Coalescence: Merge Nix-managed config with runtime state
    coalesce_config() {
      if [[ -f "$config_dir/.claude.json" && -f "$settings_file" ]]; then
        # Preserve runtime fields while applying Nix settings
        ${pkgs.jq}/bin/jq -s '.[0] as $runtime | .[1] as $settings |
          $runtime + {
            permissions: $settings.permissions,
            env: $settings.env,
            hooks: $settings.hooks,
            statusLine: $settings.statusLine
          }' "$config_dir/.claude.json" "$settings_file" > "$config_dir/.claude.json.tmp" && \
          mv "$config_dir/.claude.json.tmp" "$config_dir/.claude.json"
      fi
    }

    # Setup environment variables
    setup_environment() {
      export CLAUDE_CONFIG_DIR="$config_dir"
      ${envSetupBlock}
    }

    # Check for headless mode - bypass PID check for stateless operations
    if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
      coalesce_config
      setup_environment
      exec "${claudeBin}" --settings="$settings_file" --mcp-config="$config_dir/.mcp.json" "$@"
    fi

    # Production Claude detection logic (v2.0: check for --settings flag)
    if pgrep -f "claude.*--settings.*$settings_file" > /dev/null 2>&1; then
      coalesce_config
      setup_environment
      exec "${claudeBin}" --settings="$settings_file" --mcp-config="$config_dir/.mcp.json" "$@"
    fi

    # PID-based single instance management
    if [[ -f "$pidfile" ]]; then
      pid=$(cat "$pidfile")
      if kill -0 "$pid" 2>/dev/null; then
        echo "Claude (${displayName}) is already running (PID: $pid)"
        echo "   Using existing instance..."
        coalesce_config
        setup_environment
        exec "${claudeBin}" --settings="$settings_file" --mcp-config="$config_dir/.mcp.json" "$@"
      else
        echo "Cleaning up stale PID file..."
        rm -f "$pidfile"
      fi
    fi

    # Launch new instance with environment setup
    echo "Launching Claude (${displayName})..."
    setup_environment

    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"

    # Apply coalescence before launch
    coalesce_config

    # Store PID and execute
    echo $$ > "$pidfile"
    exec "${claudeBin}" --settings="$settings_file" --mcp-config="$config_dir/.mcp.json" "$@"
  '';

  # Generate a Termux-specific wrapper (simpler, no rbw dependency, no coalescence)
  mkTermuxWrapperScript = {
    account,
    displayName,
    api ? {},
    extraEnvVars ? {}
  }:
  let
    baseUrl = api.baseUrl or null;
    authMethod = api.authMethod or "api-key";
    disableApiKey = api.disableApiKey or false;
    modelMappings = api.modelMappings or {};
  in ''
    #!/data/data/com.termux/files/usr/bin/bash
    set -euo pipefail

    # ─── API Configuration ───────────────────────────────────────────
    ${lib.optionalString (baseUrl != null) ''
    export ANTHROPIC_BASE_URL="${baseUrl}"
    ''}
    ${lib.optionalString disableApiKey ''
    export ANTHROPIC_API_KEY=""
    ''}
    ${lib.optionalString (authMethod == "bearer") ''
    # Bearer token - read from local secrets file on Termux
    TOKEN_FILE="$HOME/.secrets/claude-${account}-token"
    if [[ -f "$TOKEN_FILE" ]]; then
      export ANTHROPIC_AUTH_TOKEN="$(cat "$TOKEN_FILE")"
    else
      echo "Warning: Bearer token not found at $TOKEN_FILE" >&2
      echo "   Create it with: mkdir -p ~/.secrets && echo 'your-token' > $TOKEN_FILE" >&2
    fi
    ''}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
    export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
    '') modelMappings)}

    # ─── Extra Environment Variables ─────────────────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
    export ${k}="${v}"
    '') extraEnvVars)}

    # ─── Config Directory ────────────────────────────────────────────
    export CLAUDE_CONFIG_DIR="$HOME/.claude-${account}"
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # ─── Launch Claude ───────────────────────────────────────────────
    exec claude "$@"
  '';
}
