# GitHub and GitLab Authentication Module
# Provides seamless GitHub and GitLab authentication using Bitwarden or SOPS
{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.githubAuth;

  # Helper function to construct rbw command based on configuration
  # Supports both old tokenName format and new item/field format
  mkRbwCommand = bwCfg:
    if bwCfg.field != null then
      ''${pkgs.rbw}/bin/rbw get --field "${bwCfg.field}" "${bwCfg.item}"''
    else if bwCfg.item != null then
      ''${pkgs.rbw}/bin/rbw get "${bwCfg.item}"''
    else
    # Backward compatibility: use tokenName if item is not set
      ''${pkgs.rbw}/bin/rbw get "${bwCfg.tokenName}"'';

  # GitHub CLI wrapper with Bitwarden token injection
  # This wrapper fetches the token from Bitwarden and exports it as GH_TOKEN
  # Used for BOTH CLI operations and git credential helper operations
  gh-with-auth = pkgs.writeShellScriptBin "gh" ''
    # Only sync rbw vault and clear cache for auth-related operations
    # This avoids unnecessary syncs for read-only operations
    if [ "$1" = "auth" ] || [ "$1" = "repo" ] || [ "$1" = "pr" ] || [ "$1" = "issue" ] || [ "$1" = "release" ]; then
      # Sync rbw to ensure we have the latest token from Bitwarden vault
      ${pkgs.rbw}/bin/rbw sync 2>/dev/null || true
      # Clear git credential cache to prevent stale token issues
      ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true
    fi

    export GH_TOKEN="$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)"
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  # GitLab CLI wrapper with Bitwarden token injection
  # This wrapper fetches the token from Bitwarden and exports it as GITLAB_TOKEN
  # Used for BOTH CLI operations and git credential helper operations
  glab-with-auth = pkgs.writeShellScriptBin "glab" ''
    # Only sync rbw vault and clear cache for auth-related operations
    # This avoids unnecessary syncs for read-only operations
    if [ "$1" = "auth" ] || [ "$1" = "repo" ] || [ "$1" = "project" ] || [ "$1" = "mr" ] || [ "$1" = "issue" ]; then
      # Sync rbw to ensure we have the latest token from Bitwarden vault
      ${pkgs.rbw}/bin/rbw sync 2>/dev/null || true
      # Clear git credential cache to prevent stale token issues
      ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true
    fi

    export GITLAB_TOKEN="$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)"
    exec ${pkgs.glab}/bin/glab "$@"
  '';

  # SOPS-based wrappers (for when mode == "sops")
  # GitHub CLI wrapper with SOPS token injection
  gh-with-auth-sops = pkgs.writeShellScriptBin "gh" ''
    ${if options ? sops then ''
      TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"
      if [ -f "$TOKEN_FILE" ]; then
        export GH_TOKEN="$(cat "$TOKEN_FILE")"
      fi
    '' else ''
      echo "Warning: SOPS mode configured but SOPS module not available" >&2
    ''}
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  # GitLab CLI wrapper with SOPS token injection
  glab-with-auth-sops = pkgs.writeShellScriptBin "glab" ''
    ${if options ? sops then ''
      TOKEN_FILE="${config.sops.secrets."${cfg.gitlab.sops.secretName}".path}"
      if [ -f "$TOKEN_FILE" ]; then
        export GITLAB_TOKEN="$(cat "$TOKEN_FILE")"
      fi
    '' else ''
      echo "Warning: SOPS mode configured but SOPS module not available" >&2
    ''}
    exec ${pkgs.glab}/bin/glab "$@"
  '';

in
{
  options.githubAuth = {
    enable = mkEnableOption "GitHub authentication";

    mode = mkOption {
      type = types.enum [ "bitwarden" "sops" ];
      default = "bitwarden";
      description = "Secret backend to use for GitHub token";
    };

    protocol = mkOption {
      type = types.enum [ "https" "ssh" ];
      default = "https";
      description = "Git protocol for GitHub operations";
    };

    bitwarden = {
      tokenName = mkOption {
        type = types.str;
        default = "github-token";
        description = ''
          Bitwarden entry name for GitHub token.
          Deprecated: Use 'item' and 'field' for more control.
        '';
      };

      item = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Bitwarden item name (e.g., "github.com").
          Takes precedence over tokenName if set.
        '';
        example = "github.com";
      };

      field = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Custom field name within the Bitwarden item.
          If null, retrieves the password field.
          Only used when 'item' is set.
        '';
        example = "token";
      };
    };

    sops = {
      secretName = mkOption {
        type = types.str;
        default = "github_token";
        description = "Secret name in SOPS file";
      };

      secretsFile = mkOption {
        type = types.path;
        default = ../../secrets/common/github.yaml;
        description = "Path to SOPS secrets file";
      };
    };

    git = {
      enableCredentialHelper = mkOption {
        type = types.bool;
        default = true;
        description = "Configure git credential helper";
      };

      cacheTimeout = mkOption {
        type = types.int;
        default = 3600;
        description = "Credential cache timeout in seconds";
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Username for HTTPS authentication.
          If null (recommended), the credential helper will provide the username.
          Only set this if you need to override the default behavior.
        '';
      };
    };

    gh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Configure GitHub CLI (gh)";
      };

      enableAliases = mkOption {
        type = types.bool;
        default = true;
        description = "Enable useful gh aliases";
      };
    };

    nix = {
      enableAccessToken = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Configure nix access-tokens for authenticated GitHub fetches.
          This prevents rate limiting errors when fetching from GitHub.
          Token will be stored in ~/.config/nix/github-token (mode 600).
        '';
      };
    };

    gitlab = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable GitLab authentication and CLI";
      };

      host = mkOption {
        type = types.str;
        default = "gitlab.com";
        description = "GitLab host (for self-hosted instances)";
      };

      bitwarden = {
        tokenName = mkOption {
          type = types.str;
          default = "gitlab-token";
          description = ''
            Bitwarden entry name for GitLab token.
            Deprecated: Use 'item' and 'field' for more control.
          '';
        };

        item = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Bitwarden item name (e.g., "gitlab.com").
            Takes precedence over tokenName if set.
          '';
          example = "gitlab.com";
        };

        field = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Custom field name within the Bitwarden item.
            If null, retrieves the password field.
            Only used when 'item' is set.
          '';
          example = "api-token";
        };
      };

      sops = {
        secretName = mkOption {
          type = types.str;
          default = "gitlab_token";
          description = "Secret name in SOPS file for GitLab";
        };

        secretsFile = mkOption {
          type = types.path;
          default = ../../secrets/common/gitlab.yaml;
          description = "Path to SOPS secrets file for GitLab";
        };
      };

      git = {
        enableCredentialHelper = mkOption {
          type = types.bool;
          default = true;
          description = "Configure git credential helper for GitLab";
        };

        userName = mkOption {
          type = types.str;
          default = "oauth2";
          description = "Username for HTTPS authentication with GitLab";
        };
      };

      glab = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Configure GitLab CLI (glab)";
        };

        enableAliases = mkOption {
          type = types.bool;
          default = true;
          description = "Enable useful glab aliases";
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Install credential refresh helper
      home.packages = [
        # Helper script to refresh credentials from Bitwarden/SOPS
        (pkgs.writeShellScriptBin "refresh-git-creds" ''
          echo "🔄 Refreshing git credentials..."

          ${if cfg.mode == "bitwarden" then ''
            # Sync Bitwarden vault
            echo "  → Syncing Bitwarden vault..."
            ${pkgs.rbw}/bin/rbw sync 2>/dev/null || echo "    ⚠️  rbw sync failed (vault may be locked)"
          '' else ''
            echo "  → Using SOPS mode (no sync needed)"
          ''}

          # Clear git credential cache
          echo "  → Clearing git credential cache..."
          ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true

          echo "✅ Credentials refreshed!"
          ${optionalString cfg.gitlab.enable ''
            echo ""
            echo "Testing GitLab authentication..."
            ${if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops}/bin/glab auth status || true
          ''}
        '')
      ] ++ (optionals (cfg.gitlab.enable && cfg.gitlab.glab.enable) [
        (if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops)
      ]);

      # Git credential configuration using wrapper scripts
      programs.git = {
        settings = mkMerge [
          (mkIf cfg.git.enableCredentialHelper {
            credential = {
              # Use the wrapped gh command for GitHub credential operations
              # The wrapper injects the token from Bitwarden/SOPS, then calls
              # the official 'gh auth git-credential' subcommand
              "https://github.com" = mkMerge [
                {
                  helper = mkForce
                    (
                      let
                        ghWrapper = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;
                      in
                      "!${ghWrapper}/bin/gh auth git-credential"
                    );
                }
                (mkIf (cfg.git.userName != null) {
                  username = cfg.git.userName;
                })
              ];
              "https://gist.github.com" = {
                helper = mkForce
                  (
                    let
                      ghWrapper = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;
                    in
                    "!${ghWrapper}/bin/gh auth git-credential"
                  );
              };
            };
          })
          # GitLab credential configuration
          (mkIf (cfg.gitlab.enable && cfg.gitlab.git.enableCredentialHelper) {
            credential."https://${cfg.gitlab.host}" = {
              username = cfg.gitlab.git.userName;
              # Use the wrapped glab command for GitLab credential operations
              helper =
                let
                  glabWrapper = if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops;
                in
                "!${glabWrapper}/bin/glab auth git-credential";
            };
          })
        ];
      };

      # GitHub CLI configuration
      programs.gh = mkIf cfg.gh.enable {
        enable = true;

        # Use our wrapper instead of the regular gh package
        package = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;

        settings = mkMerge [
          {
            git_protocol = cfg.protocol;
            # Token fetched via wrapper script (not via git credential helper)
          }
          # Additional useful aliases (merged with existing)
          (mkIf cfg.gh.enableAliases {
            aliases = {
              pv = "pr view";
              rv = "repo view";
              prs = "pr list";
              issues = "issue list";
            };
          })
        ];
      };

      # Create glab config file WITHOUT token (token provided via GITLAB_TOKEN env var)
      home.activation.glabConfig = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable)
        (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          mkdir -p "$HOME/.config/glab-cli"
          CONFIG_FILE="$HOME/.config/glab-cli/config.yml"

          # Remove symlink if it exists
          if [ -L "$CONFIG_FILE" ]; then
            rm -f "$CONFIG_FILE"
          fi

          # Create config WITHOUT token field
          cat > "$CONFIG_FILE" <<EOF
          # GitLab CLI configuration
          # Token provided via GITLAB_TOKEN environment variable at runtime
          host: ${cfg.gitlab.host}
          hosts:
            ${cfg.gitlab.host}:
              git_protocol: ${cfg.protocol}
              api_protocol: https
          display_hyperlinks: true
          glamour_style: dark
          editor: ${config.home.sessionVariables.EDITOR or "vim"}
          EOF
          chmod 600 "$CONFIG_FILE"
          $DRY_RUN_CMD echo "✅ GitLab CLI configured for ${cfg.gitlab.host} (token via env var)"
        '');

      # Bitwarden mode: informational activation check
      home.activation.githubAuthBitwarden = mkIf (cfg.mode == "bitwarden")
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Non-blocking check if rbw is unlocked
          if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
            $DRY_RUN_CMD echo "ℹ️  Note: Bitwarden vault is locked. GitHub/GitLab auth will fail until you run: rbw unlock"
          else
            $DRY_RUN_CMD echo "✅ Bitwarden unlocked - GitHub${optionalString cfg.gitlab.enable "/GitLab"} authentication ready"
          fi
        '');

      # Setup GitHub token for nix access-tokens
      home.activation.setupNixGithubToken = mkIf cfg.nix.enableAccessToken
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          TOKEN_DIR="$HOME/.config/nix"
          TOKEN_FILE="$TOKEN_DIR/github-token"

          # Create directory if it doesn't exist
          mkdir -p "$TOKEN_DIR"

          # Try to fetch token from Bitwarden/SOPS and write to file
          if [ "''${DRY_RUN:-0}" != "1" ]; then
            if [ "${cfg.mode}" = "bitwarden" ]; then
              # Try to get token from Bitwarden
              TOKEN="$(${mkRbwCommand cfg.bitwarden} 2>/dev/null || true)"
              if [ -n "$TOKEN" ]; then
                echo "$TOKEN" > "$TOKEN_FILE"
                chmod 600 "$TOKEN_FILE"
                $DRY_RUN_CMD echo "✅ GitHub token for nix stored in ~/.config/nix/github-token"
              else
                if [ -f "$TOKEN_FILE" ]; then
                  $DRY_RUN_CMD echo "ℹ️  Using existing GitHub token file for nix"
                else
                  $DRY_RUN_CMD echo "⚠️  No GitHub token found. Create one at https://github.com/settings/tokens"
                  $DRY_RUN_CMD echo "    Store it in ~/.config/nix/github-token with permissions 600"
                  $DRY_RUN_CMD echo "    Required scopes: read:packages (or just 'repo' for private repos)"
                fi
              fi
            elif [ "${cfg.mode}" = "sops" ]; then
              # SOPS mode - token should be in the decrypted secret file
              ${optionalString (options ? sops) ''
                TOKEN_SRC="${config.sops.secrets."${cfg.sops.secretName}".path}"
                if [ -f "$TOKEN_SRC" ]; then
                  cp "$TOKEN_SRC" "$TOKEN_FILE"
                  chmod 600 "$TOKEN_FILE"
                  $DRY_RUN_CMD echo "✅ GitHub token for nix copied from SOPS"
                else
                  $DRY_RUN_CMD echo "⚠️  SOPS secret not available for GitHub token"
                fi
              ''}
              ${optionalString (!(options ? sops)) ''
                $DRY_RUN_CMD echo "⚠️  SOPS mode configured but SOPS module not available"
                $DRY_RUN_CMD echo "    Please configure SOPS or switch to bitwarden mode"
              ''}
            fi
          fi
        '');

      # Configure nix to use the token file via extra-access-tokens
      # This reads the token at runtime instead of evaluation time
      nix.settings = mkIf cfg.nix.enableAccessToken {
        extra-access-tokens = "${config.home.homeDirectory}/.config/nix/github-token";
      };

      # Assertions
      assertions = [
        {
          assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
          message = "githubAuth with bitwarden mode requires secretsManagement.enable = true";
        }
        # SOPS mode assertion disabled until sops-nix module integration is fixed
        # {
        #   assertion = cfg.mode == "sops" -> ((config.sops.age.keyFile or null) != null);
        #   message = "githubAuth with sops mode requires SOPS age key configuration";
        # }
      ];

      # Warnings
      warnings =
        optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
          "githubAuth: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
    }

    # SOPS mode configuration is intentionally skipped for now
    # as the sops-nix module is not loaded in all contexts.
    # To enable SOPS support, ensure sops-nix is imported and
    # configure the secrets manually.
  ]);
}
