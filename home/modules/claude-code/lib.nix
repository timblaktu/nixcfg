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
  mkClaudeWrapperScript =
    {
      # Required parameters
      account
    , # Account name (e.g., "max", "pro", "work")
      displayName
    , # Human-readable name for messages
      configDir
    , # Path to account config directory
      claudeBin ? "${pkgs.claude-code}/bin/claude"
    , # Path to claude binary

      # Optional API configuration (from account.api options)
      api ? { }
    , # Optional secrets configuration (from account.secrets options)
      secrets ? { }
    , # Optional extra environment variables (from account.extraEnvVars)
      extraEnvVars ? { }
    }:
    let
      # Extract API options with defaults
      baseUrl = api.baseUrl or null;
      authMethod = api.authMethod or "api-key";
      disableApiKey = api.disableApiKey or false;
      modelMappings = api.modelMappings or { };

      # Extract secrets options
      bearerToken = secrets.bearerToken or null;

      # Generate API environment variable exports
      # NOTE: Claude Code requires ANTHROPIC_API_KEY for third-party proxies (not ANTHROPIC_AUTH_TOKEN)
      # ANTHROPIC_AUTH_TOKEN is for Anthropic's OAuth flow; API_KEY is used for both Anthropic API
      # and third-party endpoints when ANTHROPIC_BASE_URL is set.
      apiEnvVars = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        # ANTHROPIC_BASE_URL - set if custom baseUrl specified
        (lib.optionalString (baseUrl != null) ''
          export ANTHROPIC_BASE_URL="${baseUrl}"'')

        # ANTHROPIC_AUTH_TOKEN - retrieve via rbw if bearer auth + bitwarden configured
        # For third-party proxies (Code-Companion), use AUTH_TOKEN and blank out API_KEY
        (lib.optionalString (authMethod == "bearer" && bearerToken != null && bearerToken.bitwarden or null != null) (
          let
            bwItem = bearerToken.bitwarden.item;
            bwField = bearerToken.bitwarden.field or null;
            # If field is null/empty, use just item name (gets default password)
            # Otherwise, pass both item and field name
            rbwCmd =
              if bwField == null || bwField == ""
              then ''rbw get "${bwItem}"''
              else ''rbw get "${bwItem}" --field "${bwField}"'';
            fieldDesc =
              if bwField == null || bwField == ""
              then "(default password)"
              else "Field: ${bwField}";
          in
          ''
            # Retrieve API key from Bitwarden via rbw
            # Code-Companion proxy expects x-api-key header (sent when ANTHROPIC_API_KEY is set)
            if command -v rbw >/dev/null 2>&1; then
              ANTHROPIC_API_KEY="$(${rbwCmd} </dev/null 2>/dev/null)" || {
                echo "Warning: Failed to retrieve API key from Bitwarden" >&2
                echo "   Item: ${bwItem}, ${fieldDesc}" >&2
              }
              export ANTHROPIC_API_KEY
            else
              echo "Error: rbw (Bitwarden CLI) is required but not found" >&2
              echo "   Install rbw and configure Bitwarden access to retrieve API keys" >&2
              echo "   See: home/modules/secrets-management.nix for configuration" >&2
              exit 1
            fi''
        ))

        # ANTHROPIC_API_KEY - set to empty string only if disableApiKey is true AND no bearer auth
        (lib.optionalString (disableApiKey && authMethod != "bearer") ''
          export ANTHROPIC_API_KEY=""'')
      ]);

      # Generate model mapping environment variables
      # Maps: sonnet -> ANTHROPIC_DEFAULT_SONNET_MODEL, etc.
      modelEnvVars = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (model: mapping: ''
          export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"'')
        modelMappings);

      # Generate extra environment variable exports
      extraEnvExports = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (k: v: ''
          export ${k}="${v}"'')
        extraEnvVars);

      # Combined environment setup block
      envSetupBlock = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
        apiEnvVars
        modelEnvVars
        extraEnvExports
      ]);

    in
    ''
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

      # PID-based coalescence trigger (silent - multiple instances are allowed)
      # Note: This does NOT enforce single-instance; it ensures coalescence runs
      # when another instance exists. Per-worktree isolation planned for future.
      if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
          # Another instance exists - coalesce and launch (no blocking)
          coalesce_config
          setup_environment
          exec "${claudeBin}" --settings="$settings_file" --mcp-config="$config_dir/.mcp.json" "$@"
        else
          # Stale PID file - clean up silently
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
  mkTermuxWrapperScript =
    { account
    , displayName
    , api ? { }
    , extraEnvVars ? { }
    }:
    let
      baseUrl = api.baseUrl or null;
      authMethod = api.authMethod or "api-key";
      disableApiKey = api.disableApiKey or false;
      modelMappings = api.modelMappings or { };
    in
    ''
      #!/data/data/com.termux/files/usr/bin/bash
      set -euo pipefail

      # ─── API Configuration ───────────────────────────────────────────
      ${lib.optionalString (baseUrl != null) ''
      export ANTHROPIC_BASE_URL="${baseUrl}"
      ''}
      ${lib.optionalString (authMethod == "bearer") ''
      # API key for third-party proxy - read from local secrets file on Termux
      # NOTE: Claude Code uses ANTHROPIC_API_KEY (not AUTH_TOKEN) for proxy endpoints
      TOKEN_FILE="$HOME/.secrets/claude-${account}-token"
      if [[ -f "$TOKEN_FILE" ]]; then
        ANTHROPIC_API_KEY="$(cat "$TOKEN_FILE")"
        export ANTHROPIC_API_KEY
      else
        echo "Warning: API key not found at $TOKEN_FILE" >&2
        echo "   Create it with: mkdir -p ~/.secrets && echo 'your-token' > $TOKEN_FILE" >&2
      fi
      ''}
      ${lib.optionalString (disableApiKey && authMethod != "bearer") ''
      export ANTHROPIC_API_KEY=""
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
